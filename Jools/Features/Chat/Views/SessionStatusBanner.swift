import SwiftUI
import JoolsKit

/// A prominent banner showing the current session status with contextual messaging
struct SessionStatusBanner: View {
    let state: SessionState
    let syncState: SessionSyncState
    let isPolling: Bool
    let lastUpdatedAt: Date?
    let currentStepTitle: String?
    let currentStepDescription: String?
    let onRetry: () -> Void

    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        if let config = bannerConfig {
            VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
                HStack(alignment: .center, spacing: JoolsSpacing.sm) {
                    // For terminal / awaiting states (completed, failed,
                    // cancelled, awaiting input, awaiting plan approval)
                    // the banner shows a compact leading glyph so the
                    // state reads at a glance. For active states
                    // (running, queued, unspecified) the glyph is
                    // suppressed entirely — the headline + the sweeping
                    // gradient strip at the bottom of the banner carry
                    // the "something is happening" signal. See the
                    // overlay on the banner VStack below for the strip.
                    if !config.showSpinner {
                        Image(systemName: config.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(config.foregroundColor)
                    }

                    // Title + ellipsis composed as a single Text run so
                    // the dots flow naturally after the message instead
                    // of sitting in a fixed-width column with a left gap
                    // when only one dot is showing.
                    //
                    // Accessibility label is pinned to the STABLE title
                    // (without the animated dots) so UI tests and
                    // VoiceOver users see a deterministic string like
                    // "Jules is working" instead of the momentary
                    // "Jules is working.." / "Jules is working...".
                    // Previously the dots broke `XCUIElementQuery` because
                    // the visible text changed 2-3 times per second.
                    Text(messageWithEllipsis(config: config))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(config.foregroundColor)
                        .lineLimit(1)
                        .accessibilityLabel(config.message)

                    Spacer(minLength: 0)
                }

                // Suppress redundant currentStepTitle when it would just
                // repeat what the banner header already says (common in
                // terminal states like .completed / .failed where the
                // step title is literally "Session completed").
                if let currentStepTitle, !currentStepTitle.isEmpty,
                   currentStepTitle.caseInsensitiveCompare(config.message) != .orderedSame {
                    Text(currentStepTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chat.current-step-title")
                }

                if let currentStepDescription, !currentStepDescription.isEmpty {
                    Text(currentStepDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: JoolsSpacing.sm) {
                    Text(syncFooterText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if syncState.canRetry {
                        Button("Tap to retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(config.foregroundColor)
                            .accessibilityIdentifier("chat.retry")
                    }
                }
            }
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(config.backgroundColor)
            // Bottom edge treatment. For active states (running,
            // queued, unspecified) we show a continuously sweeping
            // 2pt gradient strip — the "something is loading"
            // convention from Xcode / GitHub / Safari / Linear.
            // For terminal and paused states we fall back to a
            // plain hairline divider so the banner still reads as
            // a contained section from the chat bubbles below.
            //
            // Important: the strip is gated on `config.showSpinner`
            // (the session state is active), NOT on `isPolling`.
            // `isPolling` is bridged from `PollingService`'s
            // `@Published var isPolling`, which only flips true
            // during the ~200-500ms window of each in-flight
            // network request. Gating the strip on `isPolling`
            // produced a "flash on for 300ms, hidden for 5s"
            // pattern that read as "abruptly stopping", because
            // we were showing network state instead of session
            // state. The strip now reflects "Jules is working"
            // (the session state) and plays continuously for the
            // entire duration of that state.
            .overlay(alignment: .bottom) {
                if config.showSpinner {
                    IndeterminateProgressStrip(tint: config.foregroundColor)
                        .frame(height: 2)
                } else {
                    Rectangle()
                        .fill(config.foregroundColor.opacity(0.18))
                        .frame(height: 0.5)
                }
            }
            .accessibilityIdentifier("chat.status-banner")
            .onReceive(timer) { _ in
                if config.animateDots {
                    dotCount = (dotCount % 3) + 1
                }
            }
        }
    }

    /// Compose the banner title with optional animated trailing
    /// ellipsis. Keeping the dots inside the same `Text` value lets
    /// SwiftUI lay them out naturally — no fixed-width column, no
    /// left gap when the dot count animates from 3 back to 1.
    private func messageWithEllipsis(config: BannerConfig) -> String {
        if config.animateDots {
            return config.message + String(repeating: ".", count: dotCount)
        }
        return config.message
    }

    private var syncFooterText: String {
        switch syncState {
        case .idle:
            if let lastUpdatedAt {
                return "\(freshnessLabel(for: lastUpdatedAt)) • Pull to refresh"
            }
            return "Pull to refresh"
        case .syncing:
            if let lastUpdatedAt {
                return "Syncing… \(freshnessLabel(for: lastUpdatedAt))"
            }
            return "Syncing…"
        case .stale(let message), .failed(let message):
            return message
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
                animateDots: true
            )

        case .queued:
            return BannerConfig(
                message: "Session queued, starting soon",
                icon: "clock.fill",
                backgroundColor: Color.orange.opacity(0.15),
                foregroundColor: Color.orange,
                showSpinner: true,
                animateDots: true
            )

        case .awaitingUserInput:
            return BannerConfig(
                message: "Jules needs your input",
                icon: "bubble.left.fill",
                backgroundColor: Color.joolsAwaiting.opacity(0.15),
                foregroundColor: Color.joolsAwaiting
            )

        case .awaitingPlanApproval:
            return BannerConfig(
                message: "Review and approve the plan",
                icon: "doc.text.fill",
                backgroundColor: Color.joolsAwaiting.opacity(0.15),
                foregroundColor: Color.joolsAwaiting
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
                animateDots: true
            )
        }
    }

    private func freshnessLabel(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)

        switch elapsed {
        case ..<30:
            return "Updated just now"
        case ..<90:
            return "Updated about a minute ago"
        case ..<3600:
            let minutes = max(1, Int(elapsed / 60))
            return "Updated \(minutes) min ago"
        default:
            return "Updated \(date.formatted(.relative(presentation: .named)))"
        }
    }
}

private struct BannerConfig {
    let message: String
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    /// When true, the banner is considered "active" — the leading
    /// glyph is suppressed and the bottom edge renders an animated
    /// indeterminate progress strip instead of a plain hairline.
    /// The name is historical (it once gated a ProgressView spinner
    /// that sat next to the title) but the flag itself still maps
    /// 1:1 to "this state represents background work in progress".
    var showSpinner: Bool = false
    var animateDots: Bool = false
}

/// Thin sweeping gradient strip used along the bottom edge of the
/// banner for "work in progress" states. Matches the silky linear-
/// sweep feel of CSS `animation: slide Xs linear infinite` used by
/// GitHub / Linear / Material Design indeterminate progress bars.
///
/// Why TWO bands, 50% phase offset apart:
///   * A single band leaves the strip visually empty for half of
///     each cycle (while the band is exiting one side and re-
///     entering the other). That reads as a "flash on, flash off"
///     pulse, not a continuous loader.
///   * Running two bands at a 50% phase offset means one is always
///     mid-sweep while the other is entering/exiting an edge —
///     continuous coverage, no perceived gaps.
///
/// Why LINEAR motion (not sine):
///   * A sine curve decelerates to zero velocity at each edge, so
///     the band visually sits still for a fraction of a second at
///     each reversal. That reads as "abrupt". Linear motion has
///     constant velocity and no visible stutter at reset time —
///     the reset moment is hidden because the band is fully
///     off-screen when it wraps back to the start.
///
/// Parameters:
///   * 1.4s cycle — brisk enough to feel active, slow enough to
///     stay ambient in peripheral vision
///   * Band width 55% of strip — overlaps half the strip at any
///     time so with two bands there's always dense coverage
///   * Rail opacity 0.22 — more visible than before so even the
///     "between-bands" moments still show a strip
private struct IndeterminateProgressStrip: View {
    let tint: Color

    private static let cyclePeriod: Double = 2.0
    private static let bandWidth: CGFloat = 0.55

    /// Evaluated once at process start. UI tests set
    /// `JOOLS_UI_TEST_DISABLE_ANIMATIONS=1` and
    /// `UIView.setAnimationsEnabled(false)` is called in
    /// `JoolsApp.init`, but `TimelineView(.animation)` is a pure
    /// SwiftUI driver that ignores that flag. Without gating here,
    /// the continuous 60fps band sweep prevents the XCUITest
    /// accessibility snapshot from settling on CI runners — causing
    /// a "Failed to get matching snapshots" cascade that wedges
    /// the whole test suite. See docs/LEARNINGS.md §
    /// "UI testing on iOS".
    private static let animationsEnabled: Bool = {
        ProcessInfo.processInfo.environment["JOOLS_UI_TEST_DISABLE_ANIMATIONS"] != "1"
    }()

    var body: some View {
        if Self.animationsEnabled {
            GeometryReader { proxy in
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let totalWidth = proxy.size.width
                    let bandSize = totalWidth * Self.bandWidth

                    ZStack(alignment: .topLeading) {
                        // Faint rail — always-visible base so the strip
                        // never reads as "suddenly there, suddenly gone".
                        Rectangle()
                            .fill(tint.opacity(0.22))

                        // Two phase-offset bands for continuous coverage.
                        movingBand(at: 0, t: t, totalWidth: totalWidth, bandSize: bandSize)
                        movingBand(at: 0.5, t: t, totalWidth: totalWidth, bandSize: bandSize)
                    }
                }
            }
            .clipped()
        } else {
            // Static fallback for UI tests. Just the rail — no
            // moving bands, no TimelineView.
            Rectangle()
                .fill(tint.opacity(0.22))
        }
    }

    /// A single gradient band with linear sawtooth motion, offset
    /// by `phaseOffset` cycles from t=0. `phaseOffset ∈ [0, 1)`.
    @ViewBuilder
    private func movingBand(
        at phaseOffset: Double,
        t: Double,
        totalWidth: CGFloat,
        bandSize: CGFloat
    ) -> some View {
        // Sawtooth phase in [0, 1): how far through the current
        // cycle the band is, accounting for the phase offset.
        let rawPhase = (t / Self.cyclePeriod + phaseOffset)
        let phase = rawPhase - floor(rawPhase)

        // Band travels from -bandSize (fully off-screen left) to
        // totalWidth (fully off-screen right). At phase 0 and
        // phase 1 the band is off-screen, so the instantaneous
        // reset from 1 → 0 is visually invisible.
        let travel = totalWidth + bandSize
        let xOffset = -bandSize + CGFloat(phase) * travel

        LinearGradient(
            colors: [
                .clear,
                tint.opacity(0.45),
                tint.opacity(0.75),
                tint.opacity(0.45),
                .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandSize)
        .offset(x: xOffset)
    }
}

/// Pixel-art Jules mascot, used by both the chat status banner and
/// the in-bubble agent avatar so the chat surface presents a single
/// consistent visual for Jules.
///
/// Three subtle changes from the original:
///
/// 1. The sparkle/icon overlay above the head was removed. The
///    banner already conveys session state via its title text + the
///    "Live" pill, so the overlay was a redundant visual indicator
///    that just looked like noise. (User feedback.)
/// 2. The float animation amplitude is now ±1pt over 1.8s — a quiet
///    "breathing" instead of the previous ±2pt over 1.15s bounce.
///    This matches the way the Jules web UI subtly animates its
///    logo. (User feedback.)
/// 3. Animation can be disabled per-call via `isAnimated: false` so
///    the small in-bubble avatar can be totally still while the
///    larger banner mascot still gently breathes.
struct PixelJulesMascot: View {
    enum Mood {
        case starting
        case queued
        case working
    }

    let mood: Mood
    let isAnimated: Bool

    init(mood: Mood, isAnimated: Bool = true) {
        self.mood = mood
        self.isAnimated = isAnimated
    }

    @State private var isFloating = false

    private let activeCells: [(x: Int, y: Int, role: Role)] = [
        (4, 0, .highlight), (5, 0, .highlight),
        (3, 1, .highlight), (4, 1, .head), (5, 1, .head), (6, 1, .highlight),
        (2, 2, .highlight), (3, 2, .head), (4, 2, .head), (5, 2, .head), (6, 2, .head), (7, 2, .highlight),
        (2, 3, .highlight), (3, 3, .head), (4, 3, .eye), (5, 3, .eye), (6, 3, .head), (7, 3, .highlight),
        (2, 4, .head), (3, 4, .head), (4, 4, .head), (5, 4, .head), (6, 4, .head), (7, 4, .head),
        (3, 5, .tentacle), (4, 5, .head), (5, 5, .head), (6, 5, .tentacle),
        (2, 6, .tentacle), (3, 6, .tentacle), (4, 6, .head), (5, 6, .head), (6, 6, .tentacle), (7, 6, .tentacle),
        (1, 7, .tentacle), (2, 7, .tentacle), (4, 7, .tentacle), (5, 7, .tentacle), (7, 7, .tentacle), (8, 7, .tentacle),
    ]

    var body: some View {
        GeometryReader { geometry in
            let gridSize = 9
            let cellSize = min(geometry.size.width, geometry.size.height) / CGFloat(gridSize)
            let pixelSize = cellSize * 0.9

            ZStack {
                ForEach(Array(activeCells.enumerated()), id: \.offset) { _, cell in
                    RoundedRectangle(cornerRadius: cellSize * 0.2, style: .continuous)
                        .fill(color(for: cell.role))
                        .frame(width: pixelSize, height: pixelSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: cellSize * 0.2, style: .continuous)
                                .stroke(Color.white.opacity(cell.role == .eye ? 0 : 0.12), lineWidth: cellSize * 0.05)
                        }
                        .offset(
                            x: CGFloat(cell.x) * cellSize + (cellSize - pixelSize) / 2,
                            y: CGFloat(cell.y) * cellSize + (cellSize - pixelSize) / 2
                        )
                }
            }
            .frame(width: CGFloat(gridSize) * cellSize, height: CGFloat(gridSize) * cellSize)
            .offset(y: isAnimated && isFloating ? -1 : (isAnimated ? 1 : 0))
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
            .animation(
                isAnimated
                    ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
                    : .default,
                value: isFloating
            )
            .onAppear {
                if isAnimated {
                    isFloating = true
                }
            }
        }
    }

    private func color(for role: Role) -> Color {
        switch role {
        case .head:
            switch mood {
            case .starting:
                return Color.joolsAccentLight
            case .queued:
                return Color.orange
            case .working:
                return Color.joolsAccent
            }
        case .highlight:
            return Color.white.opacity(0.95)
        case .tentacle:
            switch mood {
            case .starting:
                return Color.joolsAccent
            case .queued:
                return Color.orange.opacity(0.85)
            case .working:
                return Color.joolsAccentDark
            }
        case .eye:
            return Color.black.opacity(0.78)
        }
    }

    private enum Role {
        case head
        case highlight
        case tentacle
        case eye
    }
}

#Preview("Session Status Banners") {
    VStack(spacing: 0) {
        SessionStatusBanner(
            state: .running,
            syncState: .syncing,
            isPolling: true,
            lastUpdatedAt: .now.addingTimeInterval(-10),
            currentStepTitle: "Provide the summary to the user",
            currentStepDescription: "Reply to the user directly in chat with the latest findings.",
            onRetry: {}
        )
        SessionStatusBanner(
            state: .awaitingPlanApproval,
            syncState: .idle,
            isPolling: false,
            lastUpdatedAt: .now.addingTimeInterval(-42),
            currentStepTitle: "Review the generated plan",
            currentStepDescription: "Approve the plan to let Jules continue.",
            onRetry: {}
        )
        SessionStatusBanner(
            state: .completed,
            syncState: .stale(message: "Showing the last synced timeline. Pull to refresh or tap to retry."),
            isPolling: false,
            lastUpdatedAt: .now.addingTimeInterval(-120),
            currentStepTitle: "Session completed",
            currentStepDescription: nil,
            onRetry: {}
        )
    }
    .background(Color.joolsBackground)
}
