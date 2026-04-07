import Foundation
import Combine

/// Configuration for the polling service
public enum PollingConfig {
    /// Interval when user is actively viewing a session (3 seconds)
    public static let activeInterval: TimeInterval = 3.0
    /// Interval when user hasn't interacted recently (10 seconds)
    public static let idleInterval: TimeInterval = 10.0
    /// Interval when app is in background (60 seconds)
    public static let backgroundInterval: TimeInterval = 60.0
    /// Time without interaction before switching to idle mode (30 seconds)
    public static let idleThreshold: TimeInterval = 30.0
}

/// Current state of the polling service
public enum PollingState: Sendable {
    case active
    case idle
    case background
    case stopped
}

public enum PollingRefreshReason: String, Sendable {
    case initialLoad
    case foregroundResume
    case userMessageSent
    case planApproved
    case manualRefresh
    case staleRecovery
    case scheduled
}

/// Delegate protocol for receiving polling updates
@MainActor
public protocol PollingServiceDelegate: AnyObject {
    func pollingService(_ service: PollingService, didUpdateSession session: SessionDTO, reason: PollingRefreshReason)
    func pollingService(_ service: PollingService, didUpdateActivities activities: [ActivityDTO], reason: PollingRefreshReason)
    func pollingService(_ service: PollingService, didEncounterError error: Error, reason: PollingRefreshReason)
}

/// Service that manages adaptive polling for session updates
@MainActor
public final class PollingService: ObservableObject {
    // MARK: - Published Properties

    @Published public private(set) var state: PollingState = .stopped
    @Published public private(set) var isPolling: Bool = false
    @Published public private(set) var lastPollTime: Date?

    // MARK: - Properties

    public weak var delegate: PollingServiceDelegate?

    private let api: APIClient
    private var pollingTask: Task<Void, Never>?
    private var pollInFlight = false
    private var lastUserInteraction: Date = Date()
    private var activeSessionId: String?
    private var lastActivityCreateTime: Date?
    private var burstIntervals: [TimeInterval] = []

    // MARK: - Initialization

    public init(api: APIClient) {
        self.api = api
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Public API

    /// Start polling for updates on a specific session
    public func startPolling(sessionId: String, initialActivityCreateTime: Date? = nil) {
        activeSessionId = sessionId
        lastActivityCreateTime = initialActivityCreateTime
        state = .active
        lastUserInteraction = Date()
        restartPollingLoop()
    }

    /// Stop all polling
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .stopped
        isPolling = false
        activeSessionId = nil
        lastActivityCreateTime = nil
        burstIntervals = []
        pollInFlight = false
    }

    /// Call this when the user interacts with the app
    public func userDidInteract() {
        lastUserInteraction = Date()
        if state == .idle {
            state = .active
            restartPollingLoop()
        }
    }

    /// Trigger an immediate poll without waiting for the next interval.
    ///
    /// Restarts the polling loop with the supplied reason as its first
    /// poll. Previously this also spawned a separate `Task` to call
    /// `requestPoll`, which raced with the rebuilt loop and seeded a
    /// chain of queued follow-up tasks via the `requestPoll` defer
    /// block. Under burst mode that race made the @MainActor task
    /// queue grow unboundedly and froze the UI on long sessions.
    public func triggerImmediatePoll(reason: PollingRefreshReason = .manualRefresh) {
        guard activeSessionId != nil else { return }
        if reason == .userMessageSent || reason == .planApproved {
            burstIntervals = [1, 1, 2, 2, 3, 3, 3]
        }
        restartPollingLoop(initialReason: reason)
    }

    /// Notify the service that the app entered the background
    public func enterBackground() {
        guard state != .stopped else { return }
        state = .background
        restartPollingLoop()
    }

    /// Notify the service that the app entered the foreground
    public func enterForeground() {
        guard state != .stopped else { return }
        state = .active
        lastUserInteraction = Date()
        restartPollingLoop()
    }

    public func updateActivityCursor(_ createTime: Date?) {
        guard let createTime else { return }
        if let existingCreateTime = lastActivityCreateTime {
            lastActivityCreateTime = max(existingCreateTime, createTime)
        } else {
            lastActivityCreateTime = createTime
        }
    }

    // MARK: - Private Methods

    /// Cancel any in-flight polling task and start a fresh loop.
    ///
    /// The new loop polls FIRST, then sleeps for the next interval.
    /// This eliminates the previous race where `triggerImmediatePoll`
    /// spawned a separate `Task` for the immediate poll while
    /// `restartPollingLoop` simultaneously kicked off a new sleep-then-
    /// poll cycle — both fighting for the same `pollInFlight` slot.
    /// `initialReason` lets callers tag the first poll appropriately
    /// (e.g. `.planApproved`) without losing fidelity.
    private func restartPollingLoop(initialReason: PollingRefreshReason = .scheduled) {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            var nextReason = initialReason
            while !Task.isCancelled {
                guard let self = self, self.activeSessionId != nil else { break }

                self.updateStateIfNeeded()

                // Break out of loop if stopped (avoid Duration.seconds(.infinity) crash)
                guard self.state != .stopped else { break }

                await self.requestPoll(reason: nextReason)
                guard !Task.isCancelled else { break }

                let interval = self.nextInterval()
                try? await Task.sleep(for: .seconds(interval))
                nextReason = .scheduled
            }
        }
    }

    /// Run a single poll if one isn't already in flight, otherwise
    /// drop the request.
    ///
    /// Previously a duplicate request would queue a `queuedReason` and
    /// the in-flight poll's `defer` block would spawn yet another
    /// `Task` to drain the queue when it finished. That created a
    /// chained-task pattern that, under burst-mode + state-change
    /// double-fetches, accumulated faster than the @MainActor could
    /// drain it and froze the UI. Dropping duplicates is fine because
    /// the next scheduled tick (1-3s in burst, 3s active, 10s idle)
    /// will pick up any new state.
    private func requestPoll(reason: PollingRefreshReason) async {
        guard activeSessionId != nil else { return }
        guard !pollInFlight else { return }

        pollInFlight = true
        isPolling = true
        defer {
            isPolling = false
            lastPollTime = Date()
            pollInFlight = false
        }

        guard let sessionId = activeSessionId else { return }
        await performPoll(sessionId: sessionId, reason: reason)
    }

    private func performPoll(sessionId: String, reason: PollingRefreshReason) async {
        do {
            // Fetch session updates
            let session = try await api.getSession(id: sessionId)
            delegate?.pollingService(self, didUpdateSession: session, reason: reason)

            // Fetch new activities
            let activities = try await api.listAllActivities(
                sessionId: sessionId,
                pageSize: 100,
                createTime: lastActivityCreateTime
            )
            if let latestCreateTime = activities.compactMap(\.createTime).max() {
                updateActivityCursor(latestCreateTime)
            }
            delegate?.pollingService(self, didUpdateActivities: activities, reason: reason)

        } catch {
            delegate?.pollingService(self, didEncounterError: error, reason: reason)
        }
    }

    private func updateStateIfNeeded() {
        let timeSinceInteraction = Date().timeIntervalSince(lastUserInteraction)
        if timeSinceInteraction > PollingConfig.idleThreshold && state == .active {
            state = .idle
        }
    }

    private func nextInterval() -> TimeInterval {
        if state != .background, !burstIntervals.isEmpty {
            return burstIntervals.removeFirst()
        }

        switch state {
        case .active:
            return PollingConfig.activeInterval
        case .idle:
            return PollingConfig.idleInterval
        case .background:
            return PollingConfig.backgroundInterval
        case .stopped:
            return .infinity
        }
    }
}
