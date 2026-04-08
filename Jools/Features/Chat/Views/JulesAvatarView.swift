import SwiftUI
import JoolsKit

// MARK: - Jules Avatar

/// Compact pixel-mascot avatar used in chat bubbles. Shows the
/// PixelJulesMascot directly, with no circular backdrop or border —
/// the pixel art IS the avatar. A very gentle sinusoidal bob is
/// applied here (not inside PixelJulesMascot) so the chat avatar
/// feels alive without forcing an opinion on any other caller of
/// the shared mascot primitive.
///
/// Motion parameters are calibrated against a frame-by-frame
/// analysis of the official Jules web UI idle float:
///   * Peak-to-peak amplitude ≈ 12% of the mascot height
///   * Full cycle period ≈ 2.4 seconds
///   * Pure sine wave, no easing discontinuities, no horizontal
///     sway, no rotation, no scale
///
/// `TimelineView(.animation)` is the driver because a time-based
/// sine is strictly smoother than a two-state `.animation(...)` +
/// `@State` toggle (no risk of state reset on parent re-render, no
/// easeInOut discontinuities at the endpoints, exactly one phase-
/// locked source of truth).
struct JulesAvatarView: View {
    let size: CGFloat
    let isAnimated: Bool

    init(size: CGFloat = 28, isAnimated: Bool = true) {
        self.size = size
        self.isAnimated = isAnimated
    }

    // Period in seconds for one full oscillation (peak → trough → peak).
    // 2.4s matches the Jules web UI reference exactly.
    private static let bobPeriod: Double = 2.4

    // Peak amplitude in points. ±2pt on a 28pt avatar is 4pt
    // peak-to-peak ≈ 14% of avatar height — within the measured
    // 12% ratio of the web UI, slightly topped up so the motion
    // reads on iOS's denser display.
    private static let bobAmplitude: CGFloat = 2

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let y = isAnimated
                ? Self.bobAmplitude * CGFloat(sin((2 * .pi / Self.bobPeriod) * phase))
                : 0

            PixelJulesMascot(mood: .working, isAnimated: false)
                .frame(width: size, height: size)
                .offset(y: y)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Jules")
    }
}

// MARK: - Thinking Avatar

/// Avatar with animated thinking indicator
struct ThinkingAvatarView: View {
    let size: CGFloat

    @State private var rotation: Double = 0

    init(size: CGFloat = 28) {
        self.size = size
    }

    var body: some View {
        ZStack {
            // Background circle with rotating ring
            Circle()
                .fill(LinearGradient.joolsAccentGradient.opacity(0.3))

            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient.joolsAccentGradient,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))

            // Sparkle icon
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Color.joolsAccent)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(
                .linear(duration: 1)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
        .accessibilityLabel("Jules is thinking")
    }
}

// MARK: - Agent Message Bubble

/// Agent message bubble with Jules avatar
struct AgentMessageBubble: View {
    let content: String
    let timestamp: Date
    let isThinking: Bool

    init(content: String, timestamp: Date = Date(), isThinking: Bool = false) {
        self.content = content
        self.timestamp = timestamp
        self.isThinking = isThinking
    }

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.md) {
            // Avatar
            if isThinking {
                ThinkingAvatarView()
            } else {
                JulesAvatarView()
            }

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                // Message content — rendered through MarkdownText so
                // Jules's GitHub-flavored markdown (bold, lists, code
                // fences, headings, links) displays properly instead
                // of leaking through as raw source.
                MarkdownText(content)
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.vertical, JoolsSpacing.sm)
                    .background(Color.joolsBubbleAgent)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                // Timestamp
                Text(timestamp, style: .time)
                    .font(.joolsCaption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, JoolsSpacing.sm)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - Typing Indicator

/// Animated typing indicator shown when Jules is composing a response
struct TypingIndicatorView: View {
    @State private var animatingDot = 0
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.md) {
            // `isAnimated: true` (default) so the avatar bobs in
            // sync with the regular agent-message avatars. The
            // earlier design pinned it static to avoid "competing"
            // with the typing dots' bounce, but the dot animation
            // is a scale/opacity pulse and the mascot bob is a
            // vertical translation, so they don't collide — and
            // a static mascot next to bouncing dots reads as
            // "Jules is frozen". (User feedback.)
            JulesAvatarView()

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animatingDot == index ? 1.3 : 1.0)
                        .opacity(animatingDot == index ? 1.0 : 0.5)
                }
            }
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm)
            .background(Color.joolsBubbleAgent)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

            Spacer()
        }
        .padding(.horizontal, JoolsSpacing.md)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }
}

// MARK: - Working Indicator

/// Shows "Jules is working..." with activity description
struct WorkingIndicatorView: View {
    let activity: String?

    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: JoolsSpacing.sm) {
            ThinkingAvatarView(size: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("Jules is working")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)

                    Text(String(repeating: ".", count: dotCount))
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                }

                if let activity = activity {
                    Text(activity)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, JoolsSpacing.md)
        .padding(.vertical, JoolsSpacing.xs)
        .onReceive(timer) { _ in
            withAnimation {
                dotCount = (dotCount % 3) + 1
            }
        }
    }
}

// MARK: - Preview

#Preview("Jules Avatars") {
    VStack(spacing: JoolsSpacing.xl) {
        HStack(spacing: JoolsSpacing.lg) {
            VStack {
                JulesAvatarView(size: 40)
                Text("Default").font(.caption)
            }

            VStack {
                JulesAvatarView(size: 40, isAnimated: false)
                Text("Static").font(.caption)
            }

            VStack {
                ThinkingAvatarView(size: 40)
                Text("Thinking").font(.caption)
            }
        }

        Divider()

        AgentMessageBubble(
            content: "I'll help you implement this feature. Let me analyze the codebase first.",
            timestamp: Date()
        )

        AgentMessageBubble(
            content: "Processing...",
            timestamp: Date(),
            isThinking: true
        )

        TypingIndicatorView()

        WorkingIndicatorView(activity: "Analyzing codebase structure")
    }
    .padding()
    .background(Color.joolsBackground)
}
