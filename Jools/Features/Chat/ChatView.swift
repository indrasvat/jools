import SwiftUI
import SwiftData

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

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: JoolsSpacing.md) {
                        ForEach(session.activities.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { activity in
                            ActivityView(activity: activity, viewModel: viewModel)
                                .id(activity.id)
                        }
                    }
                    .padding(.vertical)
                }
                .defaultScrollAnchor(.bottom)
            }

            Divider()

            // Input bar
            ChatInputBar(viewModel: viewModel, sessionId: session.id)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dependencies.pollingService.startPolling(sessionId: session.id)
        }
        .onDisappear {
            dependencies.pollingService.stopPolling()
        }
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
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        switch activity.type {
        case .userMessaged, .agentMessaged:
            MessageBubble(activity: activity)
                .transition(.scale.combined(with: .opacity))

        case .planGenerated:
            PlanCard(
                activity: activity,
                onApprove: { viewModel.approvePlan(activityId: activity.id) },
                onReject: { viewModel.rejectPlan(activityId: activity.id) }
            )

        case .progressUpdated:
            ProgressUpdateView(activity: activity)

        case .sessionCompleted:
            SessionCompletedView(activity: activity)

        case .sessionFailed:
            SessionFailedView(activity: activity)

        default:
            EmptyView()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let activity: ActivityEntity

    private var isUser: Bool {
        activity.type == .userMessaged
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(activity.messageContent ?? "")
                    .font(.joolsBody)
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.vertical, JoolsSpacing.sm)
                    .background(isUser ? Color.joolsBubbleUser : Color.joolsBubbleAgent)
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                HStack(spacing: JoolsSpacing.xxs) {
                    Text(activity.createdAt, style: .time)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)

                    if isUser {
                        SendStatusIcon(status: activity.sendStatus)
                    }
                }
            }

            if !isUser { Spacer(minLength: 60) }
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
                .foregroundStyle(.joolsError)
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

            Button(action: { viewModel.sendMessage(sessionId: sessionId) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(viewModel.canSend ? .joolsAccent : .secondary)
            }
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, JoolsSpacing.sm)
        .background(.bar)
    }
}

// MARK: - Supporting Views

struct PlanCard: View {
    let activity: ActivityEntity
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.joolsPlanBorder)
                Text("Proposed Plan")
                    .font(.joolsHeadline)
                Spacer()
            }

            Divider()

            Text("Plan details would appear here...")
                .font(.joolsBody)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: JoolsSpacing.md) {
                Button(action: onReject) {
                    Label("Reject", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(JoolsSpacing.md)
        .background(Color.joolsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsPlanBorder, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }
}

struct ProgressUpdateView: View {
    let activity: ActivityEntity

    var body: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.joolsAccent)
            Text(activity.messageContent ?? "Working...")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

struct SessionCompletedView: View {
    let activity: ActivityEntity

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.joolsSuccess)
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
                .foregroundStyle(.joolsError)
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
        case .running:
            return .joolsRunning
        case .queued:
            return .joolsQueued
        case .awaitingUserInput:
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
