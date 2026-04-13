import SwiftUI

/// Soft-ask sheet shown before the system notification permission dialog.
/// Presented on first notifiable session transition when authorization
/// is `.notDetermined`. Follows the app's purple theme.
struct NotificationPermissionPrimer: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: JoolsSpacing.xl) {
            Spacer()

            Image(systemName: "bell.badge")
                .font(.system(size: 56))
                .foregroundStyle(Color.joolsAccent)

            VStack(spacing: JoolsSpacing.sm) {
                Text("Stay in the loop")
                    .font(.joolsTitle2)

                Text("Get notified when Jules needs your input or finishes a task. No spam — only what matters.")
                    .font(.joolsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
                Label("Plan approvals and input requests", systemImage: "exclamationmark.bubble")
                    .font(.joolsCallout)
                Label("Session completions and failures", systemImage: "checkmark.circle")
                    .font(.joolsCallout)
            }
            .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: JoolsSpacing.sm) {
                Button(action: onEnable) {
                    Text("Enable Notifications")
                        .font(.joolsHeadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.joolsAccent)
                .controlSize(.large)

                Button("Not now", action: onSkip)
                    .font(.joolsSubheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, JoolsSpacing.xl)
        .padding(.bottom, JoolsSpacing.lg)
    }
}
