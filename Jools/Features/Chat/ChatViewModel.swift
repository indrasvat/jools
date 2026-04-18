import SwiftUI
import SwiftData
import Combine
import Observation
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

/// View model for the chat view.
///
/// Migrated from `ObservableObject` + `@Published` to the Swift 5.9+
/// `@Observable` macro. The reason matters: `ObservableObject` fires
/// `objectWillChange` on EVERY `@Published` mutation, which forces
/// SwiftUI to re-run the body of every view that observes the object
/// — even views that never read the property that changed. With
/// `@Observable`, observation is **per-property**: a view that only
/// reads `inputText` is not invalidated when `lastSuccessfulSyncAt`
/// changes.
///
/// Why this matters for the freeze: under the 1 Hz burst-mode poll
/// cycle, `isPolling`, `syncState`, and `lastSuccessfulSyncAt` all
/// flip multiple times per second. Under the old `@Published` model,
/// every flip re-ran `ChatView.body`, which then walked the
/// `LazyVStack` of markdown bubbles and decided whether to invalidate
/// cell layouts. Even when SwiftUI's diff was "smart," the walk
/// itself wasn't free, and after a minute of sustained scroll the
/// main thread saturated. With per-property observation, the parent
/// `ChatView.body` doesn't invalidate when poll-status flips —
/// because it doesn't read those properties anymore. Only the small
/// `SessionStatusBanner` child view invalidates, and it doesn't own
/// the heavy timeline. (Diagnosed via simulator process samples and
/// council pass with codex + gemini, 2026-04-07.)
@MainActor
@Observable
final class ChatViewModel: PollingServiceDelegate {
    // MARK: - Observable State

    var inputText: String = ""
    var isLoading: Bool = false
    var isSending: Bool = false
    var isPolling: Bool = false
    var messageSentConfirmation: Bool = false
    var error: String?
    var showError: Bool = false
    var syncState: SessionSyncState = .idle
    var lastSuccessfulSyncAt: Date?

    // MARK: - Dependencies
    //
    // All non-view-facing internals are marked `@ObservationIgnored`
    // so they don't participate in the `@Observable` per-property
    // tracking. SwiftUI views never read these directly, so registering
    // them with the observation registrar is pure overhead and could
    // cause spurious invalidation if SwiftUI's macro decided to track
    // their reads. (Council recommendation per codex, 2026-04-07.)

    @ObservationIgnored private let logger = Logger(subsystem: "com.indrasvat.jools", category: "ChatViewModel")
    @ObservationIgnored private var apiClient: APIClient?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var pollingService: PollingService?
    @ObservationIgnored private var sessionId: String?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var optimisticReconciliationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastStaleRecoveryAt: Date?
    /// Tracks whether `configure(...)` has already wired the polling
    /// pipeline. Without this guard, repeated `onAppear` invocations
    /// (e.g. navigating back into the same chat) would stack a fresh
    /// Combine sink onto `pollingService.$isPolling` each time, so
    /// every poll tick would write to `self.isPolling` once per stale
    /// subscription. Codex flagged this as an update-amplification
    /// foot-gun in the council pass.
    @ObservationIgnored private var isConfigured = false

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var isSyncing: Bool {
        if case .syncing = syncState {
            return true
        }
        return false
    }

    // Note: no `deinit` task cancellation. Under Swift 6 strict
    // concurrency + `@Observable`, the view model is `@MainActor`-
    // isolated and `deinit` runs in a nonisolated context, so it
    // can't touch `refreshTask` or `optimisticReconciliationTasks`
    // without an isolation hop. Both task closures capture
    // `[weak self]`, so when the view model is deallocated they
    // become no-ops on their next iteration — the leak is bounded
    // and harmless.

    // MARK: - Setup

    func configure(
        apiClient: APIClient,
        modelContext: ModelContext,
        pollingService: PollingService,
        sessionId: String
    ) {
        // Idempotent configure: if we've already wired the polling
        // pipeline for this view model, don't double-subscribe. This
        // covers the case where `ChatView.onAppear` fires more than
        // once (e.g. navigating back to an existing screen, scene
        // phase wakeups). Without this guard, every `onAppear` would
        // add another `pollingService.$isPolling` Combine sink, and
        // the same poll tick would invalidate `self.isPolling` once
        // per stale subscription — exactly the kind of avoidable
        // update amplification we're trying to remove.
        guard !isConfigured else { return }
        isConfigured = true

        self.apiClient = apiClient
        self.modelContext = modelContext
        self.pollingService = pollingService
        self.sessionId = sessionId

        pollingService.delegate = self
        pollingService.updateActivityCursor(latestKnownActivityCreateTime())

        // Bridge PollingService's `@Published var isPolling` (still
        // ObservableObject under JoolsKit) into our `@Observable`
        // `isPolling` via a manual sink. `removeDuplicates()` is
        // critical: PollingService writes `isPolling` true → false →
        // true on every poll cycle, but if it ever wrote the same
        // value back-to-back we'd still trigger an Observable
        // notification — and that costs a body re-eval downstream.
        pollingService.$isPolling
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.isPolling = newValue
            }
            .store(in: &cancellables)

        applyUITestOverrides()
    }

    /// Tear down all background work owned by this view model. Called
    /// from `ChatView.onDisappear` so refresh tasks, optimistic-message
    /// reconciliation tasks, and the polling Combine sink stop doing
    /// work as soon as the user leaves the screen. Codex flagged the
    /// "trust [weak self] to deallocate" stance as too optimistic;
    /// explicit teardown is cleaner and avoids any work flicker
    /// across navigation pops. (Council recommendation, 2026-04-07.)
    func teardown() {
        refreshTask?.cancel()
        refreshTask = nil
        for task in optimisticReconciliationTasks.values {
            task.cancel()
        }
        optimisticReconciliationTasks.removeAll()
        cancellables.removeAll()
        pollingService?.delegate = nil
        isConfigured = false
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
    //
    // The two `sync*` helpers below MUST be idempotent: a poll that
    // arrives with no new information must result in zero SwiftData
    // mutations and zero `modelContext.save()` calls. Without that,
    // every poll tick fires `@Query` invalidation in the chat view,
    // SwiftUI re-runs `ChatView.body`, and the LazyVStack re-measures
    // every visible markdown bubble. Under sustained scroll plus the
    // 1 Hz burst-mode poll cycle this saturates the main thread and
    // freezes the UI — diagnosed via simulator `sample` of the frozen
    // process and confirmed by a dootsabha council pass with codex +
    // gemini. The hot stack in the sample
    // (`LazyVStackLayout.sizeThatFits`) is the symptom; the cause is
    // poll-driven view invalidation that retriggers measurement.
    //
    // The fix is structural: compare every incoming DTO field against
    // its existing entity value, only mutate on actual difference, and
    // only call `save()` if at least one field actually changed. This
    // makes a no-op poll cost zero and preserves the existing
    // observation surface for genuine updates.

    private func syncActivities(_ dtos: [ActivityDTO], sessionId: String, modelContext: ModelContext) {
        guard let session = persistedSession(sessionId: sessionId) else { return }

        let existingActivities = Dictionary(
            uniqueKeysWithValues: session.activities.filter { !$0.isOptimistic }.map { ($0.id, $0) }
        )

        let optimisticMessages = session.activities.filter { $0.isOptimistic && $0.type == .userMessaged }

        var didMutate = false

        for dto in dtos {
            if let existing = existingActivities[dto.id] {
                // Idempotent update path. Both fields are compared
                // before being written so a poll that returns the
                // same activity body produces zero SwiftData writes.
                if let contentData = try? JSONEncoder().encode(dto.content),
                   existing.contentJSON != contentData {
                    existing.contentJSON = contentData
                    didMutate = true
                }
                if let createTime = dto.createTime, existing.createdAt != createTime {
                    existing.createdAt = createTime
                    didMutate = true
                }
            } else {
                // Optimistic-message reconciliation. Deleting the
                // optimistic row is itself a mutation, so flag it.
                if dto.activityType == .userMessaged,
                   let serverMessage = dto.userMessaged?.userMessage,
                   let optimistic = optimisticMessages.first(where: { $0.messageContent == serverMessage }) {
                    optimisticReconciliationTasks[optimistic.id]?.cancel()
                    optimisticReconciliationTasks[optimistic.id] = nil
                    modelContext.delete(optimistic)
                    didMutate = true
                }

                let activity = ActivityEntity(from: dto)
                activity.session = session
                modelContext.insert(activity)
                didMutate = true
            }
        }

        if didMutate {
            try? modelContext.save()
        }
    }

    private func updateSession(_ dto: SessionDTO, sessionId: String, modelContext: ModelContext) -> SessionUpdateOutcome {
        guard let session = persistedSession(sessionId: sessionId) else {
            return SessionUpdateOutcome(stateChanged: false)
        }

        var didMutate = false
        let previousState = session.stateRaw

        // Idempotent state write — only touch the property when the
        // poll actually delivered a new state value. Same for every
        // other field below.
        if let newState = dto.state, newState != session.stateRaw {
            session.stateRaw = newState
            didMutate = true
        }
        if let newUpdatedAt = dto.updateTime, newUpdatedAt != session.updatedAt {
            session.updatedAt = newUpdatedAt
            didMutate = true
        }

        // Search ALL outputs for a pullRequest — the API can return
        // multiple outputs (e.g. changeSet + pullRequest) and the PR
        // is not guaranteed to be first.
        if let pr = dto.outputs?.lazy.compactMap({ $0.pullRequest }).first {
            if pr.url != session.prURL {
                session.prURL = pr.url
                didMutate = true
            }
            if pr.title != session.prTitle {
                session.prTitle = pr.title
                didMutate = true
            }
            if pr.description != session.prDescription {
                session.prDescription = pr.description
                didMutate = true
            }
        }

        if didMutate {
            try? modelContext.save()
        }
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
        case .running, .inProgress, .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback, .completed:
            return true
        case .queued, .failed, .paused, .cancelled, .unspecified:
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
