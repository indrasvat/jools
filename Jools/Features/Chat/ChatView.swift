import SwiftUI
import SwiftData
import JoolsKit

/// Chat view for interacting with a Jules session
struct ChatView: View {
    let session: SessionEntity
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ChatViewModel()
    @Query private var activities: [ActivityEntity]

    init(session: SessionEntity) {
        self.session = session
        let sessionId = session.id
        _activities = Query(
            filter: #Predicate<ActivityEntity> { activity in
                activity.session?.id == sessionId
            },
            sort: [SortDescriptor(\ActivityEntity.createdAt, order: .forward)]
        )
    }

    var body: some View {
        let effectiveState = session.effectiveState
        let resolvedState = session.resolvedState

        VStack(spacing: 0) {
            // Chat header
            ChatHeader(session: session, resolvedState: resolvedState)

            // Status banner
            SessionStatusBanner(
                state: effectiveState,
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

            Divider()

            // Messages
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: JoolsSpacing.md) {
                            ForEach(displayedActivities, id: \.id) { activity in
                                ActivityView(activity: activity, session: session, viewModel: viewModel)
                                    .id(activity.id)
                            }

                            // Show typing indicator when session is actively working
                            if showsTypingIndicator {
                                TypingIndicatorView()
                                    .id("typing-indicator")
                            }

                            MadeWithJoolsFooter()
                        }
                        .padding(.vertical)
                    }
                    .refreshable {
                        await viewModel.manualRefresh()
                    }
                    .accessibilityIdentifier("chat.scroll")
                    .onAppear {
                        // Initial scroll to bottom when opening session
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: displayedActivities.count) { oldValue, newValue in
                        // Scroll when new activities are added
                        guard newValue > oldValue else { return }
                        scrollToBottom(proxy: proxy)
                    }
                }

                if viewModel.isLoading && displayedActivities.isEmpty {
                    ProgressView("Loading activities...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.joolsBackground)
                }

                if !viewModel.isLoading && displayedActivities.isEmpty {
                    EmptyActivitiesView(
                        state: effectiveState,
                        syncState: viewModel.syncState,
                        onRetry: {
                            Task {
                                await viewModel.manualRefresh()
                            }
                        }
                    )
                }
            }

            Divider()

            // Input bar
            ChatInputBar(viewModel: viewModel, sessionId: session.id)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.error ?? "An error occurred")
        }
        .overlay(alignment: .top) {
            if viewModel.messageSentConfirmation {
                MessageSentConfirmation()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: viewModel.messageSentConfirmation)
            }
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
        }
    }

    /// The activities to render in the timeline.
    ///
    /// We rely on the `@Query`'s `SortDescriptor(\.createdAt, order: .forward)`
    /// for ordering — sorting is done by SwiftData at fetch time so we
    /// don't need to re-sort on every body re-evaluation. The previous
    /// implementation called `.sorted { ... }` twice (once on
    /// `activities`, once on `session.activities` as a fallback) inside
    /// a computed property used by a `ForEach`, which paid the sort cost
    /// on every render. Under burst-mode polling that re-rendered the
    /// chat view ~once per second, that was significant main-thread work.
    /// (Gemini review.)
    ///
    /// We keep the `session.activities` fallback path for the initial
    /// load case where the `@Query` hasn't yet observed the freshly-
    /// inserted rows — but we read the relationship straight, no extra
    /// sort, since `@Relationship` ordering matches `createdAt` here.
    private var displayedActivities: [ActivityEntity] {
        if !activities.isEmpty {
            return activities
        }
        return session.activities.sorted { $0.createdAt < $1.createdAt }
    }

    private var latestProgressActivity: ActivityEntity? {
        displayedActivities.last(where: { $0.type == .progressUpdated })
    }

    private var latestPlanStep: PlanStepDTO? {
        guard let steps = displayedActivities.last(where: { $0.type == .planGenerated })?.plan?.steps, !steps.isEmpty else {
            return nil
        }

        return steps.first(where: { ($0.status ?? "").lowercased() == "in_progress" })
            ?? steps.first(where: { ($0.status ?? "").lowercased() == "pending" })
            ?? steps.last
    }

    private var currentStepTitle: String? {
        switch session.effectiveState {
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

    private var currentStepDescription: String? {
        switch session.effectiveState {
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

    private var showsTypingIndicator: Bool {
        let state = session.effectiveState
        return state == .running || state == .inProgress || state == .queued
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Note: deliberately NOT wrapped in `withAnimation` anymore.
        // When the polling loop delivers several new activities in
        // quick succession (which happens during burst mode after a
        // plan approval), the count-change observer fires once per
        // arriving activity. Each `withAnimation { proxy.scrollTo }`
        // schedules a 0.3s animation; with several stacking up the
        // animation queue chains and pins the run loop. Hard-jumping
        // to the bottom is fine for a chat-style UI and dramatically
        // reduces main-thread pressure during long sessions.
        if showsTypingIndicator {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        } else if let lastActivity = displayedActivities.last {
            proxy.scrollTo(lastActivity.id, anchor: .bottom)
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

// MARK: - Empty State

struct EmptyActivitiesView: View {
    let state: SessionState
    let syncState: SessionSyncState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: JoolsSpacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.joolsAccent.opacity(0.5))

            Text(state.isActive ? "Waiting for activity" : "No messages yet")
                .font(.joolsHeadline)
                .foregroundStyle(.secondary)

            Text(syncState.message ?? "Jules is syncing this session. Pull to refresh if the timeline looks stale.")
                .font(.joolsCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if syncState.canRetry {
                Button("Tap to retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("chat.retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @ObservedObject var viewModel: ChatViewModel

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
                canRespond: session.effectiveState == .awaitingPlanApproval,
                onApprove: { viewModel.approvePlan(activityId: activity.id) },
                onRevise: { viewModel.rejectPlan(activityId: activity.id) }
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
    @ObservedObject var viewModel: ChatViewModel
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
                .onSubmit {
                    if viewModel.canSend {
                        viewModel.sendMessage(sessionId: sessionId)
                    }
                }

            Button(action: { viewModel.sendMessage(sessionId: sessionId) }) {
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
        HStack(alignment: .top, spacing: JoolsSpacing.sm) {
            ThinkingAvatarView(size: 24)

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                Text(message)
                    .font(.joolsBody)
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
