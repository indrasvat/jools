import SwiftUI
import SwiftData
import JoolsKit

/// Chat view for interacting with a Jules session.
///
/// **Observation-splitting architecture (2026-04-07).** Two earlier
/// freezes were caused by `ChatView.body` having too wide an
/// observation surface: every poll tick flipped `viewModel.isPolling`,
/// `viewModel.syncState`, and `viewModel.lastSuccessfulSyncAt`, each
/// of which re-evaluated the entire body INCLUDING the heavy
/// LazyVStack of markdown bubbles. SwiftUI then walked the LazyVStack
/// subtree on every parent re-evaluation, and even with idempotent
/// SwiftData sync the parent re-eval cost compounded badly under the
/// 1Hz burst-mode poll cycle.
///
/// The fix is to split the chat surface into three sibling views with
/// disjoint observation slices:
///
/// 1. `ChatHeader` — observes session metadata only
/// 2. `SessionStatusBanner` — observes the volatile poll state
///    (`isPolling`, `syncState`, `lastSuccessfulSyncAt`)
/// 3. `ChatMessagesList` — owns its own `@Query` of activities and
///    only re-renders when the activity set actually changes
/// 4. `ChatInputBar` — observes only `viewModel.inputText` and
///    `isSending`
///
/// `ChatView` itself only observes the session entity and the high-
/// level lifecycle state. When the polling service flips
/// `isPolling`, only the status banner re-renders — the message list
/// stays put because its inputs (the @Query subscription + the
/// session id + the canRespondToPlan flag) are unchanged. (Diagnosed
/// via simulator process sample + dootsabha council with codex +
/// gemini.)
struct ChatView: View {
    let session: SessionEntity
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    // `@State` (not `@StateObject`) is the right wrapper for an
    // `@Observable` reference type. SwiftUI tracks the object's
    // identity via `@State` and per-property reads via `@Observable`.
    @State private var viewModel = ChatViewModel()

    init(session: SessionEntity) {
        self.session = session
    }

    var body: some View {
        // CRITICAL: this body deliberately reads NOTHING that depends
        // on `session.activities` or any volatile `viewModel`
        // property. With `@Observable` (Swift 5.9+), every property
        // read inside a body establishes per-property observation
        // tracking; if the parent reads `session.effectiveState`
        // (which walks `session.activities` through the state
        // machine), every activity insert/update invalidates the
        // parent body and forces SwiftUI to re-walk the entire
        // ZStack/LazyVStack subtree. That's the
        // `dispatchImmediately → UpdateStack::update → _ZStackLayout.placeSubviews`
        // freeze pattern we hit on the all-fixes build.
        //
        // The wrapper-view pattern below moves EVERY read of either
        // volatile viewModel state or activity-derived state into
        // its own tiny child view (LiveChatChrome,
        // LiveSessionStatusBanner, ChatMessagesList,
        // MessageSentConfirmationOverlay, ErrorAlertHost,
        // RefreshToolbarButton). Each tiny view has a narrow
        // observation surface, so only the subview that observes a
        // changing property re-renders. The parent body itself only
        // observes the `session` reference identity and the
        // `viewModel` reference identity — neither of which changes
        // during normal operation. (Council pass with codex,
        // 2026-04-07.)

        VStack(spacing: 0) {
            // Chrome header + status banner. Owns ALL session-state
            // computation (effectiveState, resolvedState, currentStep
            // text). The parent body never touches session.activities.
            LiveChatChrome(session: session, viewModel: viewModel)

            Divider()

            ChatMessagesList(
                session: session,
                viewModel: viewModel
            )

            Divider()

            ChatInputBar(viewModel: viewModel, sessionId: session.id)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshToolbarButton(viewModel: viewModel)
            }
        }
        .modifier(ErrorAlertHost(viewModel: viewModel))
        .overlay(alignment: .top) {
            MessageSentConfirmationOverlay(viewModel: viewModel)
        }
        .onAppear {
            configureViewModel()
            guard !dependencies.isUITestMode else { return }

            dependencies.pollingService.startPolling(
                sessionId: session.id,
                initialActivityCreateTime: viewModel.latestKnownActivityCreateTime()
            )
            Task {
                await viewModel.loadActivities()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !dependencies.isUITestMode else { return }
            switch newPhase {
            case .active:
                Task {
                    await viewModel.handleForegroundResume()
                }
            case .background:
                dependencies.pollingService.enterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onDisappear {
            dependencies.pollingService.stopPolling()
            viewModel.teardown()
        }
    }

    private func configureViewModel() {
        viewModel.configure(
            apiClient: dependencies.apiClient,
            modelContext: modelContext,
            pollingService: dependencies.pollingService,
            sessionId: session.id
        )
    }
}

// MARK: - Chat Messages List (observation-split child)
//
// This view exists specifically to isolate the heavy LazyVStack of
// markdown bubbles from the parent's volatile poll state. The
// parent `ChatView.body` re-evaluates several times per polling
// cycle as `viewModel.isPolling`, `syncState`, and
// `lastSuccessfulSyncAt` flip. Without this split, every parent
// re-eval forces SwiftUI to walk the LazyVStack subtree and decide
// whether to invalidate cell layouts — which, with markdown bubbles
// having complex `sizeThatFits` cost, was the second freeze
// contributor (after the non-idempotent SwiftData writes that the
// codex/gemini council pass identified).
//
// `ChatMessagesList` owns its OWN `@Query` of activities. As long as
// the underlying SwiftData store doesn't actually mutate (which the
// idempotent sync ensures for unchanged polls), the @Query result is
// stable and SwiftUI can short-circuit re-renders of this view even
// when the parent re-runs its body. The parent passes only the
// session entity, the view model reference (compared by identity),
// the resolved effective state, and the canRespondToPlan flag —
// none of which change on a typical poll tick.

struct ChatMessagesList: View {
    let session: SessionEntity
    /// `@Bindable` is the `@Observable` equivalent of `@ObservedObject`.
    /// It lets the child read observable properties of the view model
    /// without forcing the parent to invalidate when those properties
    /// change — per-property tracking is the whole point.
    @Bindable var viewModel: ChatViewModel

    @Query private var activities: [ActivityEntity]

    init(
        session: SessionEntity,
        viewModel: ChatViewModel
    ) {
        self.session = session
        self.viewModel = viewModel

        let sessionId = session.id
        _activities = Query(
            filter: #Predicate<ActivityEntity> { activity in
                activity.session?.id == sessionId
            },
            sort: [SortDescriptor(\ActivityEntity.createdAt, order: .forward)]
        )
    }

    var body: some View {
        // Option B architecture (2026-04-07):
        //
        // 1. Convert the `@Query` result to `[ActivitySnapshot]` value
        //    types via `ActivitySnapshotBuilder`. This is the ONE
        //    place in the chat surface that touches SwiftData
        //    `@PersistedProperty` accessors — everything downstream
        //    is pure Sendable value types. The ForEach id keypath
        //    no longer goes through SwiftData's observation
        //    registrar, and cell recycling sees stable Equatable
        //    inputs. (Council recommendation: codex + gemini.)
        //
        // 2. Use `List` instead of `ScrollView + LazyVStack`. List
        //    is backed by `UICollectionView` under the hood with
        //    native cell recycling — the Jules web UI's advantage
        //    comes from the browser's mature layout caching, and
        //    `List` is the closest SwiftUI equivalent. `LazyVStack`
        //    has no cell-level recycling and walks every visible
        //    child on every invalidation.
        //
        // 3. Each row takes an `ActivitySnapshot` by value, so the
        //    row view tree is flat: agent markdown bubbles render
        //    via a `ForEach(segments)` of pre-computed flat
        //    `MarkdownSegment`s, not a nested walk of the
        //    swift-markdown AST.
        //
        // The markdown rendering happens ONCE when the snapshot is
        // constructed (in the snapshot builder), not on every row
        // render. Combined with the existing `MarkdownDocumentCache`,
        // repeated rebuilds of the same content are effectively
        // free. (Web UI forensic analysis: Jules web outputs ~3
        // HTML elements per markdown block; previous SwiftUI
        // MarkdownText produced ~50 nested views per block — the
        // flat-segments approach closes that 15× gap.)

        let snapshots = ActivitySnapshotBuilder.build(
            from: activities,
            fallback: session.activities
        )
        let effectiveState = session.effectiveState
        let canRespondToPlan = effectiveState == .awaitingPlanApproval
        let showsTyping = effectiveState == .running
            || effectiveState == .inProgress
            || effectiveState == .queued

        ZStack {
            if snapshots.isEmpty && viewModel.isLoading {
                ProgressView("Loading activities...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.joolsBackground)
            } else if snapshots.isEmpty {
                EmptyActivitiesView(
                    state: effectiveState,
                    syncState: viewModel.syncState,
                    onRetry: {
                        Task { await viewModel.manualRefresh() }
                    }
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(snapshots) { snapshot in
                            ActivitySnapshotRow(
                                snapshot: snapshot,
                                canRespondToPlan: canRespondToPlan,
                                onApprovePlan: { viewModel.approvePlan() },
                                onRevisePlan: { viewModel.rejectPlan() }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: JoolsSpacing.xs,
                                leading: 0,
                                bottom: JoolsSpacing.xs,
                                trailing: 0
                            ))
                        }

                        if showsTyping {
                            TypingIndicatorView()
                                .id("typing-indicator")
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(
                                    top: JoolsSpacing.xs,
                                    leading: 0,
                                    bottom: JoolsSpacing.xs,
                                    trailing: 0
                                ))
                        }

                        MadeWithJoolsFooter()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await viewModel.manualRefresh()
                    }
                    .accessibilityIdentifier("chat.scroll")
                    .onAppear {
                        scrollToBottom(
                            proxy: proxy,
                            snapshots: snapshots,
                            showsTyping: showsTyping
                        )
                    }
                    .onChange(of: snapshots.count) { oldValue, newValue in
                        guard newValue > oldValue else { return }
                        scrollToBottom(
                            proxy: proxy,
                            snapshots: snapshots,
                            showsTyping: showsTyping
                        )
                    }
                }
            }
        }
    }

    private func scrollToBottom(
        proxy: ScrollViewProxy,
        snapshots: [ActivitySnapshot],
        showsTyping: Bool
    ) {
        if showsTyping {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        } else if let lastSnapshot = snapshots.last {
            proxy.scrollTo(lastSnapshot.id, anchor: .bottom)
        }
    }
}

// MARK: - Volatile-state observer wrappers
//
// These tiny views exist solely to isolate `@Observable` property
// reads from the parent `ChatView.body`. With `@Observable` (Swift
// 5.9+), every property read inside a view's body establishes
// per-property observation tracking. If `ChatView.body` itself reads
// `viewModel.isPolling` to pass it as a parameter to a child view,
// the parent body gets invalidated on every poll tick — and the
// resulting parent re-evaluation walks the entire ZStack and
// LazyVStack subtree, triggering the
// `dispatchImmediately → UpdateStack::update → _ZStackLayout.placeSubviews`
// freeze pattern we hit on the all-fixes build.
//
// By extracting each cluster of volatile reads into its own tiny
// observer view, only THAT view's body re-runs on the corresponding
// state change. The parent body is invalidated only when truly
// stable inputs (`session`, `effectiveState`, `canRespondToPlan`)
// change — which under idempotent sync means roughly never during a
// poll cycle.

/// Wrapper that owns ALL session-state derivation (effectiveState,
/// resolvedState, current step text) plus the chat header and the
/// status banner. Crucially, every read of `session.activities` lives
/// inside THIS view's body — not the parent `ChatView.body` — so
/// activity inserts/updates only invalidate this small subtree, not
/// the heavy LazyVStack message list. (Council fix per codex,
/// 2026-04-07.)
///
/// `effectiveState` walks the entire activity timeline through the
/// state machine; if it lived in `ChatView.body`, every activity
/// arrival would re-walk the timeline AND re-walk the LazyVStack
/// subtree below. By moving it here, the parent body stays inert
/// across activity changes and the activity list re-renders
/// independently.
struct LiveChatChrome: View {
    let session: SessionEntity
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        let effectiveState = session.effectiveState
        let resolvedState = session.resolvedState
        let stepTitle = currentStepTitle(for: effectiveState)
        let stepDescription = currentStepDescription(for: effectiveState)

        VStack(spacing: 0) {
            ChatHeader(session: session, resolvedState: resolvedState)

            LiveSessionStatusBanner(
                viewModel: viewModel,
                state: effectiveState,
                currentStepTitle: stepTitle,
                currentStepDescription: stepDescription
            )
        }
    }

    /// Sorted activity timeline read directly off the SwiftData
    /// relationship. Sorted because `@Relationship` doesn't carry an
    /// ordering guarantee.
    private var displayedActivitiesForStatus: [ActivityEntity] {
        session.activities.sorted { $0.createdAt < $1.createdAt }
    }

    private var latestProgressActivity: ActivityEntity? {
        displayedActivitiesForStatus.last(where: { $0.type == .progressUpdated })
    }

    private var latestPlanStep: PlanStepDTO? {
        guard let steps = displayedActivitiesForStatus.last(where: { $0.type == .planGenerated })?.plan?.steps, !steps.isEmpty else {
            return nil
        }
        return steps.first(where: { ($0.status ?? "").lowercased() == "in_progress" })
            ?? steps.first(where: { ($0.status ?? "").lowercased() == "pending" })
            ?? steps.last
    }

    private func currentStepTitle(for state: SessionState) -> String? {
        switch state {
        case .awaitingPlanApproval:
            return latestPlanStep?.title ?? "Review the generated plan"
        case .awaitingUserInput:
            return "Jules is waiting for your input"
        case .running, .inProgress, .queued:
            return latestProgressActivity?.progressTitle ?? latestProgressActivity?.messageContent
        case .completed:
            return "Session completed"
        case .failed:
            return "Session failed"
        case .cancelled:
            return "Session cancelled"
        case .unspecified:
            return nil
        }
    }

    private func currentStepDescription(for state: SessionState) -> String? {
        switch state {
        case .awaitingPlanApproval:
            return latestPlanStep?.description
        case .awaitingUserInput:
            return "Open the latest Jules message below and reply to continue."
        case .running, .inProgress, .queued:
            return latestProgressActivity?.progressDescription
        case .completed, .failed, .cancelled, .unspecified:
            return nil
        }
    }
}

/// Tiny observer view that reads `viewModel.syncState`,
/// `isPolling`, and `lastSuccessfulSyncAt` and renders the underlying
/// stateless `SessionStatusBanner`. Only this view's body re-runs on
/// poll-tick state flips.
struct LiveSessionStatusBanner: View {
    @Bindable var viewModel: ChatViewModel
    let state: SessionState
    let currentStepTitle: String?
    let currentStepDescription: String?

    var body: some View {
        SessionStatusBanner(
            state: state,
            syncState: viewModel.syncState,
            isPolling: viewModel.isPolling,
            lastUpdatedAt: viewModel.lastSuccessfulSyncAt,
            currentStepTitle: currentStepTitle,
            currentStepDescription: currentStepDescription,
            onRetry: {
                Task {
                    await viewModel.manualRefresh()
                }
            }
        )
    }
}

/// Tiny observer view that reads `viewModel.messageSentConfirmation`
/// and renders the toast. Only this view re-runs when the toast
/// flag flips.
struct MessageSentConfirmationOverlay: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        if viewModel.messageSentConfirmation {
            MessageSentConfirmation()
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: viewModel.messageSentConfirmation)
        }
    }
}

/// View modifier that holds the error-alert state. The `.alert`
/// modifier needs a `Binding<Bool>` to the showError flag, which
/// requires reading the property — so we wrap it in a modifier that
/// only this small surface observes.
struct ErrorAlertHost: ViewModifier {
    @Bindable var viewModel: ChatViewModel

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error ?? "An error occurred")
            }
    }
}

/// Tiny observer view for the toolbar refresh button. Only re-runs
/// when `viewModel.isSyncing` changes.
struct RefreshToolbarButton: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        Button {
            Task {
                await viewModel.manualRefresh()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(viewModel.isSyncing)
        .accessibilityIdentifier("chat.refresh")
    }
}

// MARK: - Empty State

struct EmptyActivitiesView: View {
    let state: SessionState
    let syncState: SessionSyncState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: JoolsSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.joolsAccent.opacity(0.55), Color.joolsAccent.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)

            VStack(spacing: JoolsSpacing.xs) {
                Text(headlineText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subheadText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if syncState.canRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, JoolsSpacing.md)
                        .padding(.vertical, JoolsSpacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.joolsAccent)
                .accessibilityIdentifier("chat.retry")
            }
        }
        .padding(JoolsSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Short, scannable headline. Drops the "syncing" verbosity that
    /// the previous copy had — the polling activity is already shown
    /// up top in the status banner, so the empty-state headline only
    /// needs to tell the user what THIS view is doing right now.
    private var headlineText: String {
        if syncState.canRetry {
            return state.isActive ? "Couldn't load this session" : "Couldn't load activity"
        }
        return state.isActive ? "Waiting for the first message" : "No messages yet"
    }

    private var subheadText: String {
        if let message = syncState.message {
            return message
        }
        if state.isActive {
            return "Jules will start posting here as soon as it's ready."
        }
        return "Send a follow-up to keep this session moving."
    }
}

// MARK: - Chat Header

struct ChatHeader: View {
    let session: SessionEntity
    let resolvedState: ResolvedSessionState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                Text(session.title)
                    .font(.joolsHeadline)
                    .lineLimit(1)

                HStack(spacing: JoolsSpacing.xs) {
                    SessionStateBadge(resolved: resolvedState)
                    if !session.isRepoless {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(session.sourceBranch)
                            .font(.joolsCaption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Label("No repo", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                            .font(.joolsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let prURL = session.prURL, let url = URL(string: prURL) {
                Link(destination: url) {
                    Label("View PR", systemImage: "arrow.up.right.square")
                        .font(.joolsCaption)
                }
            }
        }
        .padding()
    }
}

// MARK: - Activity View

struct ActivityView: View {
    let activity: ActivityEntity
    let session: SessionEntity
    @Bindable var viewModel: ChatViewModel
    /// Provided by the parent `ChatView` so each plan card doesn't
    /// have to re-derive `session.effectiveState` (which folds the
    /// entire activity timeline through the state machine).
    let canRespondToPlan: Bool

    var body: some View {
        switch activity.type {
        case .userMessaged:
            UserMessageBubble(activity: activity)
                .transition(.scale.combined(with: .opacity))

        case .agentMessaged:
            AgentMessageBubble(
                content: activity.messageContent ?? "",
                timestamp: activity.createdAt
            )
            .transition(.scale.combined(with: .opacity))

        case .planGenerated:
            PlanCardView(
                activity: activity,
                // Only the live plan should expose Approve/Revise.
                // Historical plan cards from sessions that have moved
                // past awaiting-approval stay visible but inert.
                canRespond: canRespondToPlan,
                onApprove: { viewModel.approvePlan() },
                onRevise: { viewModel.rejectPlan() }
            )

        case .progressUpdated:
            ProgressUpdateView(activity: activity)

        case .sessionCompleted:
            CompletionCardView(
                session: session,
                activity: activity,
                diffStats: DiffStats(
                    additions: activity.diffAdditions,
                    deletions: activity.diffDeletions,
                    filesChanged: activity.changedFiles.count
                ),
                changedFiles: activity.changedFiles,
                duration: session.updatedAt.timeIntervalSince(session.createdAt)
            )

        case .sessionFailed:
            SessionFailedView(activity: activity)

        case .planApproved:
            PlanApprovedView()

        default:
            EmptyView()
        }
    }
}

// MARK: - User Message Bubble

struct UserMessageBubble: View {
    let activity: ActivityEntity

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                Text(activity.messageContent ?? "")
                    .font(.joolsBody)
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.vertical, JoolsSpacing.sm)
                    .background(Color.joolsBubbleUser)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                HStack(spacing: JoolsSpacing.xxs) {
                    Text(activity.createdAt, style: .time)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)

                    SendStatusIcon(status: activity.sendStatus)
                }
            }
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

struct SendStatusIcon: View {
    let status: JoolsKit.SendStatus

    var body: some View {
        switch status {
        case .pending:
            ProgressView()
                .scaleEffect(0.6)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(Color.joolsError)
        }
    }
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @Bindable var viewModel: ChatViewModel
    let sessionId: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: JoolsSpacing.sm) {
            TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, JoolsSpacing.sm)
                .padding(.vertical, JoolsSpacing.xs)
                .background(Color.joolsSurface)
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))
                .accessibilityIdentifier("chat.input")
                .onSubmit(send)

            Button(action: send) {
                if viewModel.isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(viewModel.canSend ? Color.joolsAccent : Color.secondary)
                }
            }
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("chat.send")
        }
        .padding(.horizontal)
        .padding(.vertical, JoolsSpacing.sm)
        .background(.bar)
    }

    /// Centralized send action so the button tap and the keyboard's
    /// return-key submit follow the exact same code path. After
    /// dispatching the message we drop focus on the text field, which
    /// dismisses the on-screen keyboard. This matters specifically
    /// for the Jules use case: unlike a peer chat where the user
    /// fires off several messages in a row, here the user sends one
    /// prompt and then needs to READ a long markdown response. Leaving
    /// the keyboard up after send eats roughly half the screen real
    /// estate and forces an extra tap to start reading. (User feedback.)
    private func send() {
        guard viewModel.canSend else { return }
        viewModel.sendMessage(sessionId: sessionId)
        isFocused = false
    }
}

// MARK: - Supporting Views

struct PlanApprovedView: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.joolsSuccess)
            Text("Plan approved - Jules is implementing...")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

struct ProgressUpdateView: View {
    let activity: ActivityEntity

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            // Show bash commands if present
            ForEach(Array(activity.bashCommands.enumerated()), id: \.offset) { _, bashOutput in
                if let command = bashOutput.command {
                    CommandCardView(
                        command: command,
                        output: bashOutput.output,
                        success: !bashOutput.isLikelyFailure,
                        isRunning: false
                    )
                }
            }

            // Show progress title/description as a "Working" card
            if let message = activity.messageContent, !message.isEmpty {
                WorkingCard(message: message)
            }
        }
    }
}

/// Card showing what Jules is currently working on
struct WorkingCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.md) {
            // Use the same pixel-mascot avatar that AgentMessageBubble
            // uses, so working/progress-update bubbles match agent
            // message bubbles visually instead of using a different
            // "rotating ring with sparkle" indicator. (UI review.)
            JulesAvatarView(size: 28)

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                // Working/progress-update bubbles can carry markdown
                // too (Jules often emits "**Analyzing:** ..." style
                // status lines) so render through MarkdownText.
                MarkdownText(message)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm)
            .background(Color.joolsBubbleAgent)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

            Spacer(minLength: 40)
        }
        .padding(.horizontal, JoolsSpacing.md)
        .accessibilityIdentifier("chat.working-card")
    }
}

struct SessionCompletedView: View {
    let activity: ActivityEntity

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.joolsSuccess)
            Text("Session completed successfully")
                .font(.joolsBody)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.joolsSuccess.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }
}

struct SessionFailedView: View {
    let activity: ActivityEntity

    var body: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.joolsError)
            Text(activity.messageContent ?? "Session failed")
                .font(.joolsBody)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.joolsError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - Session State Badge

struct SessionStateBadge: View {
    let state: ResolvedSessionState

    /// Convenience for callers that already have a known SessionState.
    init(state: JoolsKit.SessionState) {
        self.state = .known(state)
    }

    init(resolved: ResolvedSessionState) {
        self.state = resolved
    }

    var body: some View {
        HStack(spacing: JoolsSpacing.xxs) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(state.displayLabel)
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("State: \(state.displayLabel)")
    }

    private var stateColor: Color {
        switch state {
        case .known(let known):
            return Self.color(for: known)
        case .unknown:
            // Neutral pill for forward-compat states the client doesn't
            // know how to theme. Better than dropping the info or
            // pretending it's "Starting".
            return .secondary
        }
    }

    private static func color(for state: JoolsKit.SessionState) -> Color {
        switch state {
        case .running, .inProgress:
            return .joolsRunning
        case .queued:
            return .joolsQueued
        case .awaitingUserInput, .awaitingPlanApproval:
            return .joolsAwaiting
        case .completed:
            return .joolsCompleted
        case .failed:
            return .joolsFailed
        case .cancelled:
            return .joolsCancelled
        case .unspecified:
            return .secondary
        }
    }
}

// MARK: - Message Sent Confirmation

struct MessageSentConfirmation: View {
    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.joolsSuccess)

            Text("Message sent - Jules is processing")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, JoolsSpacing.md)
        .padding(.vertical, JoolsSpacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(.top, 100) // Position below header and status banner
    }
}

#Preview {
    NavigationStack {
        ChatView(session: SessionEntity(
            id: "preview",
            title: "Fix login bug",
            prompt: "Fix the login bug in the auth module",
            state: .running,
            sourceId: "github/owner/repo",
            sourceBranch: "main",
            automationMode: .autoCreatePR,
            requirePlanApproval: true,
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
    .environmentObject(AppDependency())
}
