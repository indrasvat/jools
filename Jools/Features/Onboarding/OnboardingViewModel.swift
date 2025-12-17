import JoolsKit
import SwiftUI
import UIKit

/// View model for the onboarding flow with clipboard detection
@MainActor
final class OnboardingViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Key entered manually by user
    @Published var manualKey: String = ""

    /// Key detected from clipboard
    @Published private(set) var detectedKey: String?

    /// Whether validation is in progress
    @Published private(set) var isValidating: Bool = false

    /// Whether to show key confirmation alert
    @Published var showKeyConfirmation: Bool = false

    /// Whether to show error alert
    @Published var showError: Bool = false

    /// Error message to display
    @Published private(set) var errorMessage: String = ""

    /// Whether retry is available for the current error
    @Published private(set) var canRetry: Bool = false

    // MARK: - Computed Properties

    /// Returns the last 4 characters of the detected key for display
    var detectedKeySuffix: String {
        guard let key = detectedKey, key.count >= 4 else { return "" }
        return String(key.suffix(4))
    }

    // MARK: - Private Properties

    private var keyToValidate: String?

    // MARK: - Public Methods

    /// Check clipboard for a potential Jules API key
    func checkClipboardForAPIKey() {
        guard let clipboardContent = UIPasteboard.general.string else { return }

        let trimmed = clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines)

        if looksLikeJulesAPIKey(trimmed) {
            detectedKey = trimmed
            showKeyConfirmation = true
            HapticManager.shared.mediumImpact()
        }
    }

    /// Validate and save the detected or manual key
    func validateAndSaveKey(using dependencies: AppDependency) async {
        guard let key = keyToValidate, !key.isEmpty else { return }

        isValidating = true
        defer { isValidating = false }

        do {
            let isValid = try await dependencies.authenticate(with: key)

            if isValid {
                HapticManager.shared.success()
                // Navigation handled by AppDependency state change
            } else {
                handleError("Invalid API key. Please check your key and try again.", canRetry: true)
            }
        } catch let error as NetworkError {
            handleNetworkError(error)
        } catch {
            handleError(error.localizedDescription, canRetry: true)
        }
    }

    /// Clear the detected key (user cancelled confirmation)
    func clearDetectedKey() {
        detectedKey = nil
        keyToValidate = nil
    }

    /// Use the manual key for validation
    func useManualKey() {
        keyToValidate = manualKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Methods

    /// Heuristics to detect a potential Jules API key
    private func looksLikeJulesAPIKey(_ string: String) -> Bool {
        // Strong match: 53 characters starting with "AQ."
        if string.count == 53 && string.hasPrefix("AQ.") {
            return isValidAPIKeyCharacters(string)
        }

        // Loose fallback: 40-100 characters, no whitespace, alphanumeric + special chars
        if string.count >= 40 && string.count <= 100 && !string.contains(" ") {
            return isValidAPIKeyCharacters(string)
        }

        return false
    }

    /// Validate that string contains only valid API key characters
    private func isValidAPIKeyCharacters(_ string: String) -> Bool {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return string.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    /// Handle network-specific errors
    private func handleNetworkError(_ error: NetworkError) {
        switch error {
        case .unauthorized:
            handleError("Invalid API key. Please check your key and try again.", canRetry: true)
        case .forbidden:
            handleError("Access denied. Please check your API key permissions.", canRetry: true)
        case .notFound:
            handleError("Service not found. Please try again later.", canRetry: true)
        case .rateLimited:
            handleError("Too many requests. Please wait a moment and try again.", canRetry: true)
        case .serverError:
            handleError("Server error. Please try again later.", canRetry: true)
        case .invalidResponse:
            handleError("Unexpected response from server. Please try again.", canRetry: true)
        case .apiError(let message):
            handleError(message, canRetry: true)
        case .unknown:
            handleError("An unexpected error occurred. Please try again.", canRetry: true)
        case .noAPIKey:
            handleError("No API key provided.", canRetry: false)
        case .encodingFailed:
            handleError("Failed to process request. Please try again.", canRetry: true)
        case .decodingFailed:
            handleError("Failed to process response. Please try again.", canRetry: true)
        }
    }

    /// Set error state
    private func handleError(_ message: String, canRetry: Bool) {
        errorMessage = message
        self.canRetry = canRetry
        showError = true
        HapticManager.shared.error()
    }
}

// MARK: - Alert Actions

extension OnboardingViewModel {
    /// Called when user confirms detected key
    func confirmDetectedKey() {
        keyToValidate = detectedKey
    }
}
