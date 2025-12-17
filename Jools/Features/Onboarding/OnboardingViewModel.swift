import SwiftUI

/// View model for the onboarding flow
@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    func connect(using dependencies: AppDependency) async {
        guard !apiKey.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let isValid = try await dependencies.authenticate(with: apiKey)

            if !isValid {
                errorMessage = "Invalid API key. Please check your key and try again."
                showError = true
                HapticManager.shared.error()
            } else {
                HapticManager.shared.success()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            HapticManager.shared.error()
        }
    }
}
