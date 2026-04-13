import Foundation
import JoolsKit
import os

/// A state transition worth notifying the user about.
struct NotifiableTransition: Sendable {
    let sessionId: String
    let sessionTitle: String
    let repoName: String?
    let fromState: SessionState?
    let toState: SessionState
}

/// Tracks session states across app launches and detects notifiable
/// transitions. All mutations are serialized by actor isolation —
/// safe to call from dashboard refresh, background tasks, or any
/// other concurrent path.
actor SessionStateTracker {
    static let shared = SessionStateTracker()

    private let logger = Logger(subsystem: "com.indrasvat.jools", category: "SessionStateTracker")

    // MARK: - Storage Keys

    private static let stateMapKey = "jools.stateTracker.stateMap"
    private static let hasSeededKey = "jools.stateTracker.hasSeeded"
    private static let pendingTransitionsKey = "jools.stateTracker.pendingTransitions"
    private static let primerDismissedAtKey = "jools.stateTracker.primerDismissedAt"

    // MARK: - Notifiable States

    private static let notifiableStates: Set<SessionState> = [
        .awaitingPlanApproval,
        .awaitingUserInput,
        .awaitingUserFeedback,
        .completed,
        .failed,
    ]

    // MARK: - Public API

    /// Compare incoming sessions against the last known state map.
    /// Returns transitions that are worth notifying the user about.
    /// Also prunes sessions from the map that are no longer in the
    /// API response (absence-based pruning, not time-based).
    func processTransitions(_ sessions: [SessionDTO]) -> [NotifiableTransition] {
        let defaults = UserDefaults.standard

        logger.info("processTransitions called with \(sessions.count) sessions")

        // First-launch seed: record all current states without notifying.
        let hasSeeded = defaults.bool(forKey: Self.hasSeededKey)
        if !hasSeeded {
            var map: [String: String] = [:]
            for session in sessions {
                guard let state = session.state else { continue }
                map[session.id] = state
            }
            defaults.set(map, forKey: Self.stateMapKey)
            defaults.set(true, forKey: Self.hasSeededKey)
            logger.info("Initial seed: recorded \(map.count) session states")
            return []
        }

        var stateMap = (defaults.dictionary(forKey: Self.stateMapKey) as? [String: String]) ?? [:]
        var transitions: [NotifiableTransition] = []

        logger.info("State map has \(stateMap.count) entries")

        let currentSessionIds = Set(sessions.map(\.id))

        for session in sessions {
            guard let rawState = session.state else { continue }
            let state = SessionState(rawValue: rawState) ?? .unspecified
            let previousRaw = stateMap[session.id]
            let previousState = previousRaw.flatMap { SessionState(rawValue: $0) }

            // Only notify if the state actually changed
            guard previousRaw != rawState else { continue }

            logger.info("State change: \(session.title ?? "?", privacy: .public) \(previousRaw ?? "nil", privacy: .public) → \(rawState, privacy: .public)")

            // Only notify for states that require attention or confirm completion
            guard Self.notifiableStates.contains(state) else {
                stateMap[session.id] = rawState
                continue
            }

            let repoName = extractRepoName(from: session)

            transitions.append(NotifiableTransition(
                sessionId: session.id,
                sessionTitle: session.title ?? "Untitled",
                repoName: repoName,
                fromState: previousState,
                toState: state
            ))

            stateMap[session.id] = rawState
        }

        // Absence-based pruning
        for existingId in stateMap.keys where !currentSessionIds.contains(existingId) {
            stateMap.removeValue(forKey: existingId)
        }

        defaults.set(stateMap, forKey: Self.stateMapKey)
        logger.info("processTransitions: \(transitions.count) notifiable transitions")
        return transitions
    }

    /// Queue transitions to be posted after the user grants permission.
    func queuePendingTransitions(_ transitions: [NotifiableTransition]) {
        let defaults = UserDefaults.standard
        var existing = (defaults.array(forKey: Self.pendingTransitionsKey) as? [[String: String]]) ?? []
        let encoded = transitions.map { t in
            [
                "sessionId": t.sessionId,
                "sessionTitle": t.sessionTitle,
                "repoName": t.repoName ?? "",
                "toState": t.toState.rawValue,
            ]
        }
        existing.append(contentsOf: encoded)
        defaults.set(existing, forKey: Self.pendingTransitionsKey)
    }

    /// Drain and return any queued transitions (after permission granted).
    func drainPendingTransitions() -> [NotifiableTransition] {
        let defaults = UserDefaults.standard
        guard let encoded = defaults.array(forKey: Self.pendingTransitionsKey) as? [[String: String]] else {
            return []
        }
        defaults.removeObject(forKey: Self.pendingTransitionsKey)

        return encoded.compactMap { dict in
            guard let sessionId = dict["sessionId"],
                  let title = dict["sessionTitle"],
                  let stateRaw = dict["toState"],
                  let state = SessionState(rawValue: stateRaw) else {
                return nil
            }
            let repo = dict["repoName"]
            return NotifiableTransition(
                sessionId: sessionId,
                sessionTitle: title,
                repoName: repo?.isEmpty == true ? nil : repo,
                fromState: nil,
                toState: state
            )
        }
    }

    /// Whether the notification primer was recently dismissed.
    func shouldShowPrimer() -> Bool {
        guard let dismissedAt = UserDefaults.standard.object(forKey: Self.primerDismissedAtKey) as? Date else {
            return true
        }
        // Re-ask after 7 days
        return Date().timeIntervalSince(dismissedAt) > 7 * 24 * 60 * 60
    }

    func recordPrimerDismissal() {
        UserDefaults.standard.set(Date(), forKey: Self.primerDismissedAtKey)
    }

    /// Clear all tracked state (called on sign-out).
    func clearAll() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.stateMapKey)
        defaults.removeObject(forKey: Self.hasSeededKey)
        defaults.removeObject(forKey: Self.pendingTransitionsKey)
        defaults.removeObject(forKey: Self.primerDismissedAtKey)
    }

    // MARK: - Helpers

    private func extractRepoName(from session: SessionDTO) -> String? {
        guard let source = session.sourceContext?.source else { return nil }
        // source format: "sources/github/owner/repo" or "github/owner/repo"
        let parts = source
            .replacingOccurrences(of: "sources/", with: "")
            .split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return parts.suffix(2).joined(separator: "/")
    }
}
