import SwiftUI
import JoolsKit

/// View model for the chat view
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    func sendMessage(sessionId: String) {
        guard canSend else { return }

        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        HapticManager.shared.lightImpact()

        Task {
            isLoading = true
            defer { isLoading = false }

            // TODO: Send message via API
            // TODO: Create optimistic activity entity
        }
    }

    func approvePlan(activityId: String) {
        HapticManager.shared.success()

        Task {
            // TODO: Call approve plan API
        }
    }

    func rejectPlan(activityId: String) {
        HapticManager.shared.warning()

        Task {
            // TODO: Send rejection message
        }
    }
}
