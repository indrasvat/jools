import SwiftUI
import SwiftData
import Combine
import JoolsKit
import os

enum SessionSyncState: Equatable {
    case idle
    case syncing
    case stale(message: String)
    case failed(message: String)

    var message: String? {
        switch self {
        case .idle, .syncing:
            return nil
        case .stale(let message), .failed(let message):
            return message
        }
    }

    var canRetry: Bool {
        switch self {
        case .stale, .failed:
            return true
        case .idle, .syncing:
            return false
        }
    }
}

private struct SessionUpdateOutcome {
    let stateChanged: Bool
}

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
    @Published var syncState: SessionSyncState = .idle
    @Published var lastSuccessfulSyncAt: Date?

    // MARK: - Dependencies

    private let logger = Logger(subsystem: "com.indrasvat.jools", category: "ChatViewModel")
    private var apiClient: APIClient?
    private var modelContext: ModelContext?
    private var pollingService: PollingService?
    private var sessionId: String?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var optimisticReconciliationTasks: [String: Task<Void, Never>] = [:]
    private var lastStaleRecoveryAt: Date?

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var isSyncing: Bool {
        if case .syncing = syncState {
            return true
        }
        return false
    }

    deinit {
        refreshTask?.cancel()
        optimisticReconciliationTasks.values.forEach { $0.cancel() }
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

        pollingService.delegate = self
        pollingService.updateActivityCursor(latestKnownActivityCreateTime())

        pollingService.$isPolling
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPolling)

        applyUITestOverrides()
    }

    func latestKnownActivityCreateTime() -> Date? {
        guard let session = persistedSession() else { return nil }
        return session.activities
            .filter { !$0.isOptimistic }
            .map(\.createdAt)
            .max()
    }

    // MARK: - Refresh

    func loadActivities() async {
        await refreshSession(reason: .initialLoad, hardRefresh: true)
    }

    func manualRefresh() async {
        pollingService?.triggerImmediatePoll(reason: .manualRefresh)
        await refreshSession(reason: .manualRefresh, hardRefresh: true)
    }

    func handleForegroundResume() async {
        pollingService?.enterForeground()
        await refreshSession(reason: .foregroundResume, hardRefresh: true)
    }

    private func refreshSession(reason: PollingRefreshReason, hardRefresh: Bool) async {
        refreshTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(reason: reason, hardRefresh: hardRefresh)
        }

        refreshTask = task
        await task.value

        if refreshTask?.isCancelled == false {
            refreshTask = nil
        }
    }

    private func performRefresh(reason: PollingRefreshReason, hardRefresh: Bool) async {
        guard let apiClient, let sessionId, let modelContext else { return }

        let shouldBlockLoad = !hasPersistedActivities()
        if shouldBlockLoad {
            isLoading = true
        }
        syncState = .syncing

        defer {
            if shouldBlockLoad {
                isLoading = false
            }
        }

        do {
            let session = try await apiClient.getSession(id: sessionId)
            let activities: [ActivityDTO]
            do {
                if hardRefresh {
                    activities = try await apiClient.listAllActivities(sessionId: sessionId, pageSize: 100)
                } else {
                    activities = try await apiClient.listAllActivities(
                        sessionId: sessionId,
                        pageSize: 100,
                        createTime: latestKnownActivityCreateTime()
                    )
                }
            } catch NetworkError.notFound {
                activities = []
            }

            try Task.checkCancellation()

            let outcome = updateSession(session, sessionId: sessionId, modelContext: modelContext)
            syncActivities(activities, sessionId: sessionId, modelContext: modelContext)
            if let latestCreateTime = activities.compactMap(\.createTime).max() {
                pollingService?.updateActivityCursor(latestCreateTime)
            }
            handleSuccessfulSync(reason: reason, receivedActivities: activities, stateChanged: outcome.stateChanged)
        } catch is CancellationError {
            logger.debug("Cancelled refresh for \(reason.rawValue, privacy: .public)")
        } catch {
            handleSyncFailure(error, reason: reason)
        }
    }

    // MARK: - Send Message

    func sendMessage(sessionId: String) {
        guard canSend, let apiClient, let modelContext else { return }

        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        HapticManager.shared.lightImpact()

        let optimisticActivity = ActivityEntity(optimisticMessage: message)

        if let session = persistedSession(sessionId: sessionId) {
            optimisticActivity.session = session
            modelContext.insert(optimisticActivity)
            try? modelContext.save()
        }

        Task {
            isSending = true
            defer { isSending = false }

            do {
                try await apiClient.sendMessage(sessionId: sessionId, message: message)
                optimisticActivity.sendStatusRaw = SendStatus.sent.rawValue
                try? modelContext.save()

                messageSentConfirmation = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        self.messageSentConfirmation = false
                    }
                }

                syncState = .syncing
                pollingService?.triggerImmediatePoll(reason: .userMessageSent)
                scheduleOptimisticReconciliation(
                    activityId: optimisticActivity.id,
                    expectedMessage: message,
                    sessionId: sessionId
                )

                HapticManager.shared.success()
            } catch {
                optimisticActivity.sendStatusRaw = SendStatus.failed.rawValue
                try? modelContext.save()

                self.error = error.localizedDescription
                self.showError = true
                self.syncState = .failed(message: "Message failed to send.")

                HapticManager.shared.error()
            }
        }
    }

    // MARK: - Plan Actions

    func approvePlan() {
        guard let apiClient, let sessionId else { return }

        HapticManager.shared.success()
        syncState = .syncing

        Task {
            do {
                try await apiClient.approvePlan(sessionId: sessionId)
                pollingService?.triggerImmediatePoll(reason: .planApproved)
            } catch {
                self.error = error.localizedDescription
                self.showError = true
                self.syncState = .failed(message: "Plan approval did not reach Jules.")
                HapticManager.shared.error()
            }
        }
    }

    func rejectPlan() {
        guard let apiClient, let sessionId else { return }

        HapticManager.shared.warning()
        syncState = .syncing

        Task {
            do {
                try await apiClient.sendMessage(
                    sessionId: sessionId,
                    message: "Please revise this plan. I'd like to discuss changes before proceeding."
                )
                pollingService?.triggerImmediatePoll(reason: .userMessageSent)
            } catch {
                self.error = error.localizedDescription
                self.showError = true
                self.syncState = .failed(message: "Plan revision request did not reach Jules.")
                HapticManager.shared.error()
            }
        }
    }

    // MARK: - PollingServiceDelegate

    // MARK: - PollingServiceDelegate
    //
    // These methods are intentionally NOT `nonisolated`. Both the
    // delegate protocol (`PollingServiceDelegate`) and the calling
    // type (`PollingService`) are `@MainActor`, and `ChatViewModel`
    // itself is `@MainActor`, so the natural isolation is to inherit
    // main-actor isolation throughout. The previous implementation
    // wrapped each method body in `Task { @MainActor in ... }`, which
    // spawned an unstructured task per delegate call and removed
    // ordering / backpressure between deliveries. Under burst-mode
    // polling that fan-out was a major contributor to the @MainActor
    // saturation freeze. (Codex review.)

    func pollingService(_ service: PollingService, didUpdateSession session: SessionDTO, reason: PollingRefreshReason) {
        guard let modelContext, let sessionId = self.sessionId else { return }
        // Persist the new session state. We DO NOT trigger
        // triggerStaleRecoveryIfNeeded here even on a state change —
        // the polling cycle that just delivered this session is the
        // SAME cycle that's about to deliver fresh activities via
        // didUpdateActivities below. Re-running refreshSession
        // (which performs another full getSession + listAllActivities
        // round trip) doubled all the API + SwiftData + SwiftUI work
        // per poll tick.
        _ = updateSession(session, sessionId: sessionId, modelContext: modelContext)
    }

    func pollingService(_ service: PollingService, didUpdateActivities activities: [ActivityDTO], reason: PollingRefreshReason) {
        guard let modelContext, let sessionId = self.sessionId else { return }
        syncActivities(activities, sessionId: sessionId, modelContext: modelContext)
        if let latestCreateTime = activities.compactMap(\.createTime).max() {
            service.updateActivityCursor(latestCreateTime)
        }
        handleSuccessfulSync(reason: reason, receivedActivities: activities, stateChanged: false)
    }

    func pollingService(_ service: PollingService, didEncounterError error: Error, reason: PollingRefreshReason) {
        handleSyncFailure(error, reason: reason)
    }

    // MARK: - SwiftData Sync

    private func syncActivities(_ dtos: [ActivityDTO], sessionId: String, modelContext: ModelContext) {
        guard let session = persistedSession(sessionId: sessionId) else { return }

        let existingActivities = Dictionary(
            uniqueKeysWithValues: session.activities.filter { !$0.isOptimistic }.map { ($0.id, $0) }
        )

        let optimisticMessages = session.activities.filter { $0.isOptimistic && $0.type == .userMessaged }

        for dto in dtos {
            if let existing = existingActivities[dto.id] {
                if let contentData = try? JSONEncoder().encode(dto.content) {
                    existing.contentJSON = contentData
                }
                existing.createdAt = dto.createTime ?? existing.createdAt
            } else {
                if dto.activityType == .userMessaged,
                   let serverMessage = dto.userMessaged?.userMessage,
                   let optimistic = optimisticMessages.first(where: { $0.messageContent == serverMessage }) {
                    optimisticReconciliationTasks[optimistic.id]?.cancel()
                    optimisticReconciliationTasks[optimistic.id] = nil
                    modelContext.delete(optimistic)
                }

                let activity = ActivityEntity(from: dto)
                activity.session = session
                modelContext.insert(activity)
            }
        }

        try? modelContext.save()
    }

    private func updateSession(_ dto: SessionDTO, sessionId: String, modelContext: ModelContext) -> SessionUpdateOutcome {
        guard let session = persistedSession(sessionId: sessionId) else {
            return SessionUpdateOutcome(stateChanged: false)
        }

        let previousState = session.stateRaw
        session.stateRaw = dto.state ?? session.stateRaw
        session.updatedAt = dto.updateTime ?? Date()

        if let output = dto.outputs?.first?.pullRequest {
            session.prURL = output.url
            session.prTitle = output.title
            session.prDescription = output.description
        }

        try? modelContext.save()
        return SessionUpdateOutcome(stateChanged: previousState != session.stateRaw)
    }

    // MARK: - Private Helpers

    private func persistedSession(sessionId: String? = nil) -> SessionEntity? {
        guard let modelContext, let sessionId = sessionId ?? self.sessionId else { return nil }
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func hasPersistedActivities() -> Bool {
        !(persistedSession()?.activities.isEmpty ?? true)
    }

    private func handleSuccessfulSync(
        reason: PollingRefreshReason,
        receivedActivities: [ActivityDTO],
        stateChanged: Bool
    ) {
        lastSuccessfulSyncAt = Date()
        syncState = .idle

        if stateChanged && receivedActivities.isEmpty {
            logger.debug("State changed without new activities for \(reason.rawValue, privacy: .public)")
        }
    }

    private func handleSyncFailure(_ error: Error, reason: PollingRefreshReason) {
        logger.error("Sync failure for \(reason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")

        if hasPersistedActivities() {
            syncState = .stale(message: "Showing the last synced timeline. Pull to refresh or tap to retry.")
        } else {
            syncState = .failed(message: "Couldn’t load this session. Tap to retry.")
        }

        if reason == .manualRefresh || reason == .foregroundResume {
            self.error = error.localizedDescription
            self.showError = true
        }
    }

    private func scheduleOptimisticReconciliation(
        activityId: String,
        expectedMessage: String,
        sessionId: String
    ) {
        optimisticReconciliationTasks[activityId]?.cancel()
        optimisticReconciliationTasks[activityId] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(15))
            await MainActor.run {
                self.syncState = .syncing
            }
            await self.refreshSession(reason: .staleRecovery, hardRefresh: true)

            await MainActor.run {
                guard let session = self.persistedSession(sessionId: sessionId),
                      let optimistic = session.activities.first(where: {
                          $0.id == activityId && $0.isOptimistic && $0.messageContent == expectedMessage
                      }) else {
                    self.optimisticReconciliationTasks[activityId] = nil
                    return
                }

                optimistic.sendStatusRaw = SendStatus.failed.rawValue
                try? self.modelContext?.save()
                self.syncState = .failed(message: "The sent message never reconciled with Jules. Tap to retry.")
                self.optimisticReconciliationTasks[activityId] = nil
            }
        }
    }

    private func shouldTriggerStaleRecovery(for session: SessionDTO) -> Bool {
        guard let state = session.state.flatMap({ SessionState(rawValue: $0) }) else {
            return false
        }

        switch state {
        case .running, .inProgress, .awaitingPlanApproval, .awaitingUserInput, .completed:
            return true
        case .queued, .failed, .cancelled, .unspecified:
            return false
        }
    }

    private func triggerStaleRecoveryIfNeeded() async {
        let now = Date()
        if let lastStaleRecoveryAt, now.timeIntervalSince(lastStaleRecoveryAt) < 5 {
            return
        }
        lastStaleRecoveryAt = now
        await refreshSession(reason: .staleRecovery, hardRefresh: true)
    }

    private func applyUITestOverrides() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["JOOLS_UI_TEST_MODE"] == "1" else { return }

        lastSuccessfulSyncAt = Date().addingTimeInterval(-45)

        switch environment["JOOLS_UI_TEST_SYNC_STATE"] {
        case "stale":
            syncState = .stale(message: "Showing the last synced timeline. Pull to refresh or tap to retry.")
        case "failed":
            syncState = .failed(message: "Couldn’t load this session. Tap to retry.")
        default:
            syncState = .idle
        }
    }
}
