import SafariServices
import SwiftUI

/// Onboarding view for API key entry with Safari-based flow
struct OnboardingView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var showingSafari = false
    @State private var showingManualEntry = false

    private var titleGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [.white, .white.opacity(0.9), Color(hex: "C084FC")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color.primary, Color.primary.opacity(0.92), Color.joolsAccentDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .primary.opacity(0.72)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .primary.opacity(0.58)
    }

    private var buildInfoColor: Color {
        colorScheme == .dark ? .white.opacity(0.4) : .primary.opacity(0.38)
    }

    private var loadingOverlayTint: Color {
        colorScheme == .dark ? .black.opacity(0.5) : .white.opacity(0.4)
    }

    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientBackground(colorScheme: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: JoolsSpacing.xl) {
                Spacer()

                // Logo section
                VStack(spacing: JoolsSpacing.md) {
                    AppIconView()

                    Text("Jataayu")
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1.5)
                        .foregroundStyle(titleGradient)

                    VStack(spacing: 4) {
                        Text("Watch over Jules.")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(secondaryTextColor)

                        Text("An unofficial iOS client for Google's\nautonomous coding agent.")
                            .font(.joolsCaption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(tertiaryTextColor)
                    }

                    // Feature pills
                    FeaturePillsView()
                        .padding(.top, JoolsSpacing.md)
                }

                Spacer()

                // Action buttons
                VStack(spacing: JoolsSpacing.md) {
                    // Primary: Open Safari to get API key
                    Button(action: { showingSafari = true }) {
                        HStack(spacing: JoolsSpacing.xs) {
                            Image(systemName: "safari")
                            Text("Connect to Jules")
                        }
                        .font(.joolsBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient.joolsAccentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
                    }
                    .accessibilityIdentifier("onboarding.connect")

                    // Secondary: Manual entry
                    Button(action: { showingManualEntry = true }) {
                        Text("I already have a key")
                            .font(.joolsCaption)
                            .foregroundStyle(tertiaryTextColor)
                    }
                    .accessibilityIdentifier("onboarding.manualEntry")
                }
                .padding(.horizontal, JoolsSpacing.lg)

                Spacer()

                // Build info footer
                Text(BuildInfo.debugDescription)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(buildInfoColor)
                    .padding(.bottom, JoolsSpacing.sm)
            }
        }
        .fullScreenCover(isPresented: $showingSafari) {
            SafariView(url: URL(string: "https://jules.google.com/settings/api")!)
                .onDisappear {
                    viewModel.checkClipboardForAPIKey()
                }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualKeyEntrySheet(viewModel: viewModel)
        }
        .alert("Use this API key?", isPresented: $viewModel.showKeyConfirmation) {
            Button("Use Key") {
                viewModel.confirmDetectedKey()
                Task {
                    await viewModel.validateAndSaveKey(using: dependencies)
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.clearDetectedKey()
            }
        } message: {
            Text("Found key ending in ...\(viewModel.detectedKeySuffix)")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
            if viewModel.canRetry {
                Button("Retry") {
                    Task {
                        await viewModel.validateAndSaveKey(using: dependencies)
                    }
                }
            }
        } message: {
            Text(viewModel.errorMessage)
        }
        .overlay {
            // Loading overlay
            if viewModel.isValidating {
                loadingOverlayTint
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: JoolsSpacing.md) {
                            ProgressView()
                                .tint(colorScheme == .dark ? .white : .joolsAccent)
                                .scaleEffect(1.5)
                            Text("Validating...")
                                .font(.joolsBody)
                                .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                        }
                        .padding(JoolsSpacing.xl)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))
                    }
            }
        }
    }
}

// MARK: - Safari Wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Manual Entry Sheet

struct ManualKeyEntrySheet: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var isKeyRevealed = false

    private var trimmedKey: String {
        viewModel.manualKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConnect: Bool { !trimmedKey.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: JoolsSpacing.lg) {
                Text("Paste your Jules API key below")
                    .font(.joolsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, JoolsSpacing.lg)

                keyInputField

                pasteFromClipboardButton

                connectButton

                Spacer()
            }
            .padding(.horizontal, JoolsSpacing.lg)
            .navigationTitle("Enter API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Give the sheet a moment to settle before bringing up the
                // keyboard — doing it too early can swallow the first tap.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
    }

    // MARK: - Field

    @ViewBuilder
    private var keyInputField: some View {
        HStack(spacing: JoolsSpacing.sm) {
            Group {
                if isKeyRevealed {
                    TextField("AQ.…", text: $viewModel.manualKey)
                } else {
                    SecureField("AQ.…", text: $viewModel.manualKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit(attemptConnect)
            .focused($isFocused)
            .accessibilityIdentifier("manual-api-key-field")

            Button {
                isKeyRevealed.toggle()
                HapticManager.shared.selection()
            } label: {
                Image(systemName: isKeyRevealed ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(isKeyRevealed ? "Hide key" : "Show key")
        }
        .padding(.horizontal, JoolsSpacing.md)
        .padding(.vertical, JoolsSpacing.sm)
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsAccent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Paste button

    @ViewBuilder
    private var pasteFromClipboardButton: some View {
        Button(action: pasteFromClipboard) {
            HStack(spacing: JoolsSpacing.xs) {
                Image(systemName: "doc.on.clipboard")
                Text("Paste from Clipboard")
            }
            .font(.joolsBody.weight(.medium))
            .foregroundStyle(Color.joolsAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, JoolsSpacing.sm + 2)
            .background(Color.joolsAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: JoolsRadius.md)
                    .stroke(Color.joolsAccent.opacity(0.35), lineWidth: 1)
            )
        }
        .accessibilityIdentifier("paste-api-key-button")
    }

    // MARK: - Connect button

    @ViewBuilder
    private var connectButton: some View {
        Button(action: attemptConnect) {
            Text("Connect")
                .font(.joolsBody)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canConnect ? Color.joolsAccent : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        }
        .disabled(!canConnect)
        .accessibilityIdentifier("connect-api-key-button")
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        guard let clipboard = pasteboard.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboard.isEmpty
        else {
            HapticManager.shared.error()
            return
        }
        viewModel.manualKey = clipboard
        HapticManager.shared.success()
    }

    private func attemptConnect() {
        guard canConnect else { return }
        viewModel.manualKey = trimmedKey
        viewModel.useManualKey()
        dismiss()
        Task {
            await viewModel.validateAndSaveKey(using: dependencies)
        }
    }
}

// MARK: - Supporting Views

struct AnimatedGradientBackground: View {
    let colorScheme: ColorScheme
    @State private var animateGradient = false

    private var baseBackground: Color {
        colorScheme == .dark ? Color(hex: "0A0A0F") : Color(hex: "F7F4FF")
    }

    private var primaryOrb: Color {
        colorScheme == .dark ? Color.joolsAccent.opacity(0.3) : Color.joolsAccent.opacity(0.16)
    }

    private var secondaryOrb: Color {
        colorScheme == .dark ? Color.joolsAccentSecondary.opacity(0.25) : Color.joolsAccentSecondary.opacity(0.12)
    }

    private var tertiaryOrb: Color {
        colorScheme == .dark ? Color.joolsAccentDark.opacity(0.2) : Color.joolsAccentDark.opacity(0.08)
    }

    var body: some View {
        ZStack {
            baseBackground

            // Animated gradient orbs
            Circle()
                .fill(primaryOrb)
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animateGradient ? -50 : 50, y: animateGradient ? -100 : -50)

            Circle()
                .fill(secondaryOrb)
                .frame(width: 250, height: 250)
                .blur(radius: 60)
                .offset(x: animateGradient ? 80 : -80, y: animateGradient ? 150 : 100)

            Circle()
                .fill(tertiaryOrb)
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(x: animateGradient ? -30 : 30, y: animateGradient ? 50 : -50)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

struct AppIconView: View {
    @State private var isPulsing = false

    var body: some View {
        PixelJoolsBadge(cornerRadius: 24) {
            PixelJoolsMark()
                .padding(14)
        }
        .frame(width: 100, height: 100)
        .shadow(color: .joolsAccent.opacity(0.5), radius: isPulsing ? 30 : 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct FeaturePillsView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Anchored to what the public Jules REST API actually exposes —
    // each pill maps to a flow that genuinely works on this client.
    //
    // Wording is deliberately concrete about what the app does, not
    // what the phrase might *imply*:
    //   - "Triage inbox"     — Home surfaces a "Needs Attention"
    //                          section (DashboardView) that pulls
    //                          sessions waiting on your input or
    //                          plan approval to the top, so you
    //                          open the app and see only what
    //                          actually needs you.
    //   - "Quick capture"    — create a repoless session in two
    //                          taps. Great for "I had an idea"
    //                          moments that shouldn't require
    //                          scrolling a source picker. Wired
    //                          through CreateSessionRequest.repoless.
    //   - "Approve plans"    — tap Approve/Revise on a plan card.
    //   - "Chat with Jules"  — two-way conversation. Send follow-
    //                          ups mid-run (with optimistic UI),
    //                          watch step-by-step progress stream
    //                          in via adaptive polling, respond
    //                          when Jules asks for input.
    //   - "View diffs"       — per-file unified diff viewer for
    //                          completed sessions (not PR *review*
    //                          — you can't comment/approve/merge
    //                          from here; that needs GitHub API
    //                          access outside the Jules REST
    //                          surface).
    //
    // Order is load-bearing: Triage + Quick capture read first
    // because they describe what the Home screen does the moment
    // you sign in. The rest read as what you do once you open a
    // session.
    let features = [
        ("tray.2.fill",                        "Triage inbox"),
        ("sparkles",                           "Quick capture"),
        ("checkmark.seal.fill",                "Approve plans"),
        ("bubble.left.and.bubble.right.fill",  "Chat with Jules"),
        ("doc.text.magnifyingglass",           "View diffs"),
    ]

    var body: some View {
        FlowLayout(spacing: JoolsSpacing.xs) {
            ForEach(features, id: \.1) { icon, title in
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(Color.joolsAccent)
                    Text(title)
                }
                .font(.joolsCaption)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.85) : Color.primary.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    colorScheme == .dark
                        ? Color.joolsAccent.opacity(0.12)
                        : Color.white.opacity(0.72)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            colorScheme == .dark
                                ? Color.joolsAccent.opacity(0.4)
                                : Color.joolsAccent.opacity(0.22),
                            lineWidth: 1
                        )
                )
                .clipShape(Capsule())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Result of arranging the FeaturePill subviews into rows. Pulled
    /// out of `arrange(...)` so it can return a single named value
    /// instead of a 4-tuple (which trips the SwiftLint large_tuple rule).
    private struct ArrangedLayout {
        let size: CGSize
        let positions: [CGPoint]
        let rowWidths: [CGFloat]
        let rowIndices: [Int]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let result = arrange(maxWidth: maxWidth, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = arrange(maxWidth: bounds.width, subviews: subviews)

        // Center each row
        for (index, position) in result.positions.enumerated() {
            let rowWidth = result.rowWidths[result.rowIndices[index]]
            let xOffset = (bounds.width - rowWidth) / 2
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x + xOffset, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> ArrangedLayout {
        var positions: [CGPoint] = []
        var rowWidths: [CGFloat] = []
        var rowIndices: [Int] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowIndex = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                rowWidths.append(currentRowWidth - spacing)
                currentRowIndex += 1
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
                currentRowWidth = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowIndices.append(currentRowIndex)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            currentRowWidth = currentX
        }
        rowWidths.append(currentRowWidth - spacing)

        let totalWidth = rowWidths.max() ?? 0
        return ArrangedLayout(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions,
            rowWidths: rowWidths,
            rowIndices: rowIndices
        )
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppDependency())
}
