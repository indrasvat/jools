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

/// Delegate protocol for receiving polling updates
@MainActor
public protocol PollingServiceDelegate: AnyObject {
    func pollingService(_ service: PollingService, didUpdateSession session: SessionDTO)
    func pollingService(_ service: PollingService, didUpdateActivities activities: [ActivityDTO])
    func pollingService(_ service: PollingService, didEncounterError error: Error)
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
    private var lastUserInteraction: Date = Date()
    private var activeSessionId: String?

    // MARK: - Initialization

    public init(api: APIClient) {
        self.api = api
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Public API

    /// Start polling for updates on a specific session
    public func startPolling(sessionId: String) {
        activeSessionId = sessionId
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
    }

    /// Call this when the user interacts with the app
    public func userDidInteract() {
        lastUserInteraction = Date()
        if state == .idle {
            state = .active
            restartPollingLoop()
        }
    }

    /// Trigger an immediate poll without waiting for the next interval
    public func triggerImmediatePoll() {
        guard let sessionId = activeSessionId else { return }
        Task {
            await performPoll(sessionId: sessionId)
        }
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

    // MARK: - Private Methods

    private func restartPollingLoop() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, let sessionId = self.activeSessionId else { break }

                self.isPolling = true
                await self.performPoll(sessionId: sessionId)
                self.isPolling = false
                self.lastPollTime = Date()

                self.updateStateIfNeeded()

                // Break out of loop if stopped (avoid Duration.seconds(.infinity) crash)
                guard self.state != .stopped else { break }

                let interval = self.currentInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func performPoll(sessionId: String) async {
        do {
            // Fetch session updates
            let session = try await api.getSession(id: sessionId)
            delegate?.pollingService(self, didUpdateSession: session)

            // Fetch new activities
            let activitiesResponse = try await api.listActivities(sessionId: sessionId, pageSize: 30)
            delegate?.pollingService(self, didUpdateActivities: activitiesResponse.allItems)

        } catch {
            delegate?.pollingService(self, didEncounterError: error)
        }
    }

    private func updateStateIfNeeded() {
        let timeSinceInteraction = Date().timeIntervalSince(lastUserInteraction)
        if timeSinceInteraction > PollingConfig.idleThreshold && state == .active {
            state = .idle
        }
    }

    private var currentInterval: TimeInterval {
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
