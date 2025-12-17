import SwiftUI

/// Onboarding view for API key entry
struct OnboardingView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientBackground()
                .ignoresSafeArea()

            VStack(spacing: JoolsSpacing.xl) {
                Spacer()

                // Logo section
                VStack(spacing: JoolsSpacing.md) {
                    AppIconView()

                    Text("Jools")
                        .font(.joolsLargeTitle)
                        .foregroundStyle(.white)

                    Text("Your Pocket CTO")
                        .font(.joolsTitle3)
                        .foregroundStyle(.white.opacity(0.8))

                    // Feature pills
                    FeaturePillsView()
                        .padding(.top, JoolsSpacing.md)
                }

                Spacer()

                // API Key input section
                VStack(spacing: JoolsSpacing.md) {
                    VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                        Text("API KEY")
                            .font(.joolsCaption)
                            .foregroundStyle(.white.opacity(0.7))
                            .textCase(.uppercase)

                        SecureField("Enter your Jules API key", text: $viewModel.apiKey)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
                    }

                    Button(action: {
                        Task {
                            await viewModel.connect(using: dependencies)
                        }
                    }) {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.joolsAccent)
                    .disabled(viewModel.apiKey.isEmpty || viewModel.isLoading)

                    Link("Get your API key from jules.google.com",
                         destination: URL(string: "https://jules.google.com/settings")!)
                        .font(.joolsCaption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, JoolsSpacing.lg)

                Spacer()
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

// MARK: - Supporting Views

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            Color(hex: "0A0A0F")

            // Animated gradient orbs
            Circle()
                .fill(Color.joolsAccent.opacity(0.3))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animateGradient ? -50 : 50, y: animateGradient ? -100 : -50)

            Circle()
                .fill(Color.joolsAccentSecondary.opacity(0.25))
                .frame(width: 250, height: 250)
                .blur(radius: 60)
                .offset(x: animateGradient ? 80 : -80, y: animateGradient ? 150 : 100)

            Circle()
                .fill(Color.joolsAccentDark.opacity(0.2))
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
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient.joolsAccentGradient)
                .frame(width: 100, height: 100)
                .shadow(color: .joolsAccent.opacity(0.5), radius: isPulsing ? 30 : 20)

            Image(systemName: "layers.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct FeaturePillsView: View {
    let features = [
        ("checkmark.circle.fill", "Plan Review"),
        ("clock.fill", "Real-time Updates"),
        ("wifi.slash", "Offline Ready"),
    ]

    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            ForEach(features, id: \.1) { icon, title in
                HStack(spacing: JoolsSpacing.xxs) {
                    Image(systemName: icon)
                        .foregroundStyle(Color.joolsAccent)
                    Text(title)
                }
                .font(.joolsCaption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, JoolsSpacing.sm)
                .padding(.vertical, JoolsSpacing.xs)
                .background(.ultraThinMaterial.opacity(0.5))
                .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppDependency())
}
