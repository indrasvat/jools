import SwiftUI
import SwiftData
import JoolsKit

/// Chat view for interacting with a Jules session
struct ChatView: View {
    let session: SessionEntity
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            ChatHeader(session: session)

            // Status banner
            SessionStatusBanner(state: session.state, isPolling: viewModel.isPolling)

            Divider()

            // Messages
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: JoolsSpacing.md) {
                            ForEach(sortedActivities, id: \.id) { activity in
                                ActivityView(activity: activity, session: session, viewModel: viewModel)
                                    .id(activity.id)
                            }

                            // Show typing indicator when session is actively working
                            if session.state == .running || session.state == .inProgress || session.state == .queued {
                                TypingIndicatorView()
                                    .id("typing-indicator")
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: session.activities.count) { oldValue, newValue in
                        // Only scroll when new activities are added
                        guard newValue > oldValue, let last = sortedActivities.last else { return }
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }

                if viewModel.isLoading && session.activities.isEmpty {
                    ProgressView("Loading activities...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.joolsBackground)
                }

                if !viewModel.isLoading && session.activities.isEmpty {
                    EmptyActivitiesView()
                }
            }

            Divider()

            // Input bar
            ChatInputBar(viewModel: viewModel, sessionId: session.id)
        }
        .navigationBarTitleDisplayMode(.inline)
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
            dependencies.pollingService.startPolling(sessionId: session.id)
            Task {
                await viewModel.loadActivities()
            }
        }
        .onDisappear {
            dependencies.pollingService.stopPolling()
        }
    }

    private var sortedActivities: [ActivityEntity] {
        session.activities.sorted { $0.createdAt < $1.createdAt }
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
    var body: some View {
        VStack(spacing: JoolsSpacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.joolsAccent.opacity(0.5))

            Text("No messages yet")
                .font(.joolsHeadline)
                .foregroundStyle(.secondary)

            Text("Jules is working on your task.\nMessages will appear here.")
                .font(.joolsCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chat Header

struct ChatHeader: View {
    let session: SessionEntity

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                Text(session.title)
                    .font(.joolsHeadline)
                    .lineLimit(1)

                HStack(spacing: JoolsSpacing.xs) {
                    SessionStateBadge(state: session.state)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(session.sourceBranch)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
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
                onApprove: { viewModel.approvePlan(activityId: activity.id) },
                onRevise: { viewModel.rejectPlan(activityId: activity.id) }
            )

        case .progressUpdated:
            ProgressUpdateView(activity: activity)

        case .sessionCompleted:
            CompletionCardView(
                session: session,
                activity: activity,
                diffStats: .empty, // TODO: Parse from API response when available
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
    let state: JoolsKit.SessionState

    var body: some View {
        HStack(spacing: JoolsSpacing.xxs) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(state.displayName)
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
    }

    private var stateColor: Color {
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
