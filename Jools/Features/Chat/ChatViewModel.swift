import SwiftUI
import SwiftData
import Combine
import JoolsKit

/// View model for the chat view
@MainActor
final class ChatViewModel: ObservableObject, PollingServiceDelegate {
    // MARK: - Published State

    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var isPolling: Bool = false
    @Published var messageSentConfirmation: Bool = false
    @Published var error: String?
    @Published var showError: Bool = false

    // MARK: - Dependencies

    private var apiClient: APIClient?
    private var modelContext: ModelContext?
    private var pollingService: PollingService?
    private var sessionId: String?
    private var cancellables = Set<AnyCancellable>()

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Setup

    func configure(
        apiClient: APIClient,
        modelContext: ModelContext,
        pollingService: PollingService,
        sessionId: String
    ) {
        self.apiClient = apiClient
        self.modelContext = modelContext
        self.pollingService = pollingService
        self.sessionId = sessionId

        // Set self as delegate
        pollingService.delegate = self

        // Observe polling state
        pollingService.$isPolling
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPolling)
    }

    // MARK: - Initial Load

    func loadActivities() async {
        guard let apiClient, let sessionId, let modelContext else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.listActivities(sessionId: sessionId, pageSize: 50)
            syncActivities(response.allItems, sessionId: sessionId, modelContext: modelContext)
        } catch NetworkError.notFound {
            // Newly created sessions may not have activities yet - this is not an error
            // The polling service will fetch activities as they become available
        } catch {
            self.error = error.localizedDescription
            self.showError = true
        }
    }

    // MARK: - Send Message

    func sendMessage(sessionId: String) {
        guard canSend, let apiClient, let modelContext else { return }

        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        HapticManager.shared.lightImpact()

        // Create optimistic activity
        let optimisticActivity = ActivityEntity(optimisticMessage: message)

        // Find session and attach activity
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            optimisticActivity.session = session
            modelContext.insert(optimisticActivity)
            try? modelContext.save()
        }

        Task {
            isSending = true
            defer { isSending = false }

            do {
                try await apiClient.sendMessage(sessionId: sessionId, message: message)

                // Update optimistic activity status
                optimisticActivity.sendStatusRaw = SendStatus.sent.rawValue
                try? modelContext.save()

                // Show brief confirmation
                self.messageSentConfirmation = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    self.messageSentConfirmation = false
                }

                // Trigger immediate poll to get agent response
                pollingService?.triggerImmediatePoll()

                HapticManager.shared.success()
            } catch {
                // Mark as failed
                optimisticActivity.sendStatusRaw = SendStatus.failed.rawValue
                try? modelContext.save()

                self.error = error.localizedDescription
                self.showError = true

                HapticManager.shared.error()
            }
        }
    }

    // MARK: - Plan Actions

    func approvePlan(activityId: String) {
        guard let apiClient, let sessionId else { return }

        HapticManager.shared.success()

        Task {
            do {
                try await apiClient.approvePlan(sessionId: sessionId)
                // Trigger poll to get updated state
                pollingService?.triggerImmediatePoll()
            } catch {
                self.error = error.localizedDescription
                self.showError = true
                HapticManager.shared.error()
            }
        }
    }

    func rejectPlan(activityId: String) {
        guard let apiClient, let sessionId else { return }

        HapticManager.shared.warning()

        // Rejecting a plan is done by sending a message asking Jules to revise
        Task {
            do {
                try await apiClient.sendMessage(
                    sessionId: sessionId,
                    message: "Please revise this plan. I'd like to discuss changes before proceeding."
                )
                pollingService?.triggerImmediatePoll()
            } catch {
                self.error = error.localizedDescription
                self.showError = true
                HapticManager.shared.error()
            }
        }
    }

    // MARK: - PollingServiceDelegate

    nonisolated func pollingService(_ service: PollingService, didUpdateSession session: SessionDTO) {
        Task { @MainActor in
            guard let modelContext, let sessionId = self.sessionId else { return }
            updateSession(session, sessionId: sessionId, modelContext: modelContext)
        }
    }

    nonisolated func pollingService(_ service: PollingService, didUpdateActivities activities: [ActivityDTO]) {
        Task { @MainActor in
            guard let modelContext, let sessionId = self.sessionId else { return }
            syncActivities(activities, sessionId: sessionId, modelContext: modelContext)
        }
    }

    nonisolated func pollingService(_ service: PollingService, didEncounterError error: Error) {
        Task { @MainActor in
            // Don't show transient polling errors to user unless critical
            print("Polling error: \(error.localizedDescription)")
        }
    }

    // MARK: - SwiftData Sync

    private func syncActivities(_ dtos: [ActivityDTO], sessionId: String, modelContext: ModelContext) {
        // Find the session
        let sessionDescriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        )
        guard let session = try? modelContext.fetch(sessionDescriptor).first else { return }

        // Get existing activities as a dictionary for quick lookup
        let existingActivities = Dictionary(
            uniqueKeysWithValues: session.activities.filter { !$0.isOptimistic }.map { ($0.id, $0) }
        )

        // Get optimistic user messages for deduplication
        let optimisticMessages = session.activities.filter { $0.isOptimistic && $0.type == .userMessaged }

        for dto in dtos {
            if let existing = existingActivities[dto.id] {
                // Update existing activity with fresh content (includes artifacts)
                if let contentData = try? JSONEncoder().encode(dto.content) {
                    existing.contentJSON = contentData
                }
            } else {
                // Check if this is a user message that matches an optimistic one
                if dto.activityType == .userMessaged,
                   let serverMessage = dto.userMessaged?.userMessage {
                    // Find and remove matching optimistic message
                    if let optimistic = optimisticMessages.first(where: { $0.messageContent == serverMessage }) {
                        modelContext.delete(optimistic)
                    }
                }

                // Insert new activity
                let activity = ActivityEntity(from: dto)
                activity.session = session
                modelContext.insert(activity)
            }
        }

        try? modelContext.save()
    }

    private func updateSession(_ dto: SessionDTO, sessionId: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        )
        guard let session = try? modelContext.fetch(descriptor).first else { return }

        // Update session state
        session.stateRaw = dto.state ?? session.stateRaw
        session.updatedAt = dto.updateTime ?? Date()

        if let output = dto.outputs?.first?.pullRequest {
            session.prURL = output.url
            session.prTitle = output.title
            session.prDescription = output.description
        }

        try? modelContext.save()
    }
}
