import SwiftUI
import JoolsKit

// MARK: - Session Status Banner

/// A prominent banner showing the current session status with contextual messaging
struct SessionStatusBanner: View {
    let state: SessionState
    let isPolling: Bool

    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        if let config = bannerConfig {
            HStack(spacing: JoolsSpacing.sm) {
                // Status icon or spinner
                if config.showSpinner {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(config.foregroundColor)
                } else {
                    Image(systemName: config.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(config.foregroundColor)
                }

                // Status message with animated dots for active states
                HStack(spacing: 0) {
                    Text(config.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(config.foregroundColor)

                    if config.animateDots {
                        Text(String(repeating: ".", count: dotCount))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(config.foregroundColor)
                            .frame(width: 20, alignment: .leading)
                    }
                }

                Spacer()

                // Polling indicator
                if isPolling && config.showPollingIndicator {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption2)
                            .foregroundStyle(config.foregroundColor.opacity(0.8))
                    }
                }

                // Action hint for states that need user action
                if let actionHint = config.actionHint {
                    Image(systemName: actionHint)
                        .font(.caption)
                        .foregroundStyle(config.foregroundColor.opacity(0.7))
                }
            }
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm)
            .background(config.backgroundColor)
            .onReceive(timer) { _ in
                if config.animateDots {
                    dotCount = (dotCount % 3) + 1
                }
            }
        }
    }

    private var bannerConfig: BannerConfig? {
        switch state {
        case .running, .inProgress:
            return BannerConfig(
                message: "Jules is working",
                icon: "gearshape.2.fill",
                backgroundColor: Color.joolsAccent.opacity(0.15),
                foregroundColor: Color.joolsAccent,
                showSpinner: true,
                animateDots: true,
                showPollingIndicator: true
            )

        case .queued:
            return BannerConfig(
                message: "Session queued, starting soon",
                icon: "clock.fill",
                backgroundColor: Color.orange.opacity(0.15),
                foregroundColor: Color.orange,
                showSpinner: true,
                animateDots: true,
                showPollingIndicator: true
            )

        case .awaitingUserInput:
            return BannerConfig(
                message: "Jules needs your input to continue",
                icon: "bubble.left.fill",
                backgroundColor: Color.joolsAwaiting.opacity(0.15),
                foregroundColor: Color.joolsAwaiting,
                actionHint: "chevron.down"
            )

        case .awaitingPlanApproval:
            return BannerConfig(
                message: "Review and approve the plan",
                icon: "doc.text.fill",
                backgroundColor: Color.joolsAwaiting.opacity(0.15),
                foregroundColor: Color.joolsAwaiting,
                actionHint: "chevron.down"
            )

        case .completed:
            return BannerConfig(
                message: "Session completed",
                icon: "checkmark.circle.fill",
                backgroundColor: Color.joolsSuccess.opacity(0.15),
                foregroundColor: Color.joolsSuccess
            )

        case .failed:
            return BannerConfig(
                message: "Session encountered an error",
                icon: "exclamationmark.triangle.fill",
                backgroundColor: Color.joolsError.opacity(0.15),
                foregroundColor: Color.joolsError
            )

        case .cancelled:
            return BannerConfig(
                message: "Session was cancelled",
                icon: "xmark.circle.fill",
                backgroundColor: Color.secondary.opacity(0.15),
                foregroundColor: Color.secondary
            )

        case .unspecified:
            return BannerConfig(
                message: "Jules is starting up",
                icon: "hourglass",
                backgroundColor: Color.joolsAccent.opacity(0.15),
                foregroundColor: Color.joolsAccent,
                showSpinner: true,
                animateDots: true,
                showPollingIndicator: true
            )
        }
    }
}

// MARK: - Banner Configuration

private struct BannerConfig {
    let message: String
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    var showSpinner: Bool = false
    var animateDots: Bool = false
    var showPollingIndicator: Bool = false
    var actionHint: String? = nil
}

// MARK: - Preview

#Preview("Session Status Banners") {
    VStack(spacing: 0) {
        SessionStatusBanner(state: .running, isPolling: true)
        SessionStatusBanner(state: .queued, isPolling: true)
        SessionStatusBanner(state: .awaitingUserInput, isPolling: false)
        SessionStatusBanner(state: .awaitingPlanApproval, isPolling: false)
        SessionStatusBanner(state: .completed, isPolling: false)
        SessionStatusBanner(state: .failed, isPolling: false)
    }
    .background(Color.joolsBackground)
}
