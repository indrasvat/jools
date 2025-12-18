import SwiftUI
import JoolsKit

// MARK: - Command Execution View

/// Displays an executed command with expandable output
struct CommandCardView: View {
    let command: String
    let output: String?
    let success: Bool
    let isRunning: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Command header
            Button(action: {
                guard !isRunning && output != nil else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: JoolsSpacing.sm) {
                    // Status icon
                    statusIcon

                    // "Ran:" label
                    Text("Ran:")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)

                    // Command text
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Expand chevron (only if has output)
                    if output != nil && !isRunning {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.horizontal, JoolsSpacing.md)
                .padding(.vertical, JoolsSpacing.sm)
            }
            .buttonStyle(.plain)

            // Expandable output
            if isExpanded, let output = output {
                commandOutput(output)
            }
        }
        .background(Color.joolsSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.sm)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, JoolsSpacing.md)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIcon: some View {
        if isRunning {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? Color.joolsSuccess : Color.joolsError)
                .font(.body)
        }
    }

    private func commandOutput(_ output: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(output)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(JoolsSpacing.sm)
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
        .padding(.horizontal, JoolsSpacing.sm)
        .padding(.bottom, JoolsSpacing.sm)
    }
}

// MARK: - Command Activity Row

/// A simpler inline version for the activity feed
struct CommandActivityRow: View {
    let command: String
    let success: Bool

    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? Color.joolsSuccess : Color.joolsError)
                .font(.caption)

            Text("Ran:")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)

            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - Running Command Card

/// Shows a command that's currently being executed
struct RunningCommandCard: View {
    let command: String
    let liveOutput: String?

    @State private var dotCount = 1

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            // Header
            HStack(spacing: JoolsSpacing.sm) {
                ProgressView()
                    .scaleEffect(0.7)

                Text("Running:")
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)

                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            // Live output (if available)
            if let output = liveOutput {
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .padding(JoolsSpacing.xs)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
            }
        }
        .padding(JoolsSpacing.md)
        .background(Color.joolsAccent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsAccent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - Preview

#Preview("Command Card - Success") {
    VStack(spacing: JoolsSpacing.md) {
        CommandCardView(
            command: "mkdir -p mockups/flows",
            output: nil,
            success: true,
            isRunning: false
        )

        CommandCardView(
            command: "npm run build",
            output: """
            > build
            > webpack --mode production

            asset main.js 1.23 MiB [emitted] (name: main)
            asset styles.css 45.2 KiB [emitted] (name: styles)
            webpack compiled successfully in 4523 ms
            """,
            success: true,
            isRunning: false
        )

        CommandCardView(
            command: "npm test",
            output: "FAIL: 3 tests failed",
            success: false,
            isRunning: false
        )

        RunningCommandCard(
            command: "npm install",
            liveOutput: "Installing dependencies..."
        )
    }
    .padding()
    .background(Color.joolsBackground)
}
