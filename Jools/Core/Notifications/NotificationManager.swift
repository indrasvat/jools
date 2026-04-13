import Foundation
import UserNotifications
import JoolsKit
import os

/// Manages local notification scheduling, permission, categories, and
/// foreground suppression. This is the single entry point for all
/// notification logic in the app.
@MainActor
final class NotificationManager: ObservableObject {
    // MARK: - Published State

    /// Set by the UNUserNotificationCenterDelegate when a notification
    /// is tapped. Observed by MainTabView to navigate to the session.
    @Published var pendingSessionId: String?

    // MARK: - Foreground Suppression

    /// The session ID currently being viewed in ChatView. Notifications
    /// for this session are suppressed in the `willPresent` delegate.
    /// Also synced to `NotificationBridge` so the `AppDelegate` can
    /// check it without accessing the SwiftUI environment.
    var currentlyViewedSessionId: String? {
        didSet { NotificationBridge.shared.currentlyViewedSessionId = currentlyViewedSessionId }
    }

    // MARK: - Dependencies

    let stateTracker: SessionStateTracker
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "com.indrasvat.jools", category: "NotificationManager")

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        self.stateTracker = SessionStateTracker()
        registerCategories()
    }

    // MARK: - Permission

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization \(granted ? "granted" : "denied")")
        } catch {
            logger.error("Notification authorization error: \(error.localizedDescription)")
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Transition Checking

    /// Called by DashboardViewModel after syncing all sessions. Detects
    /// state transitions and posts notifications for notifiable ones.
    func checkForTransitions(_ sessions: [SessionDTO]) async {
        logger.info("checkForTransitions: \(sessions.count) sessions")
        let transitions = await stateTracker.processTransitions(sessions)
        logger.info("checkForTransitions: \(transitions.count) transitions")
        guard !transitions.isEmpty else { return }

        let status = await authorizationStatus()

        switch status {
        case .notDetermined:
            // Queue the transitions — the primer will be shown, and
            // after granting, the queued transitions will be posted.
            await stateTracker.queuePendingTransitions(transitions)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .joolsShouldShowNotificationPrimer,
                    object: nil
                )
            }
        case .authorized:
            await postNotifications(for: transitions)
        default:
            // .denied or .provisional — don't post
            break
        }
    }

    /// Post queued transitions after the user grants permission.
    func postQueuedTransitions() async {
        let queued = await stateTracker.drainPendingTransitions()
        await postNotifications(for: queued)
    }

    // MARK: - Notification Posting

    private func postNotifications(for transitions: [NotifiableTransition]) async {
        // Read settings directly from UserDefaults (safe from any context)
        let defaults = UserDefaults.standard
        let notifyOnComplete = defaults.object(forKey: "notifyOnComplete") as? Bool ?? true
        let notifyOnNeedsInput = defaults.object(forKey: "notifyOnNeedsInput") as? Bool ?? true
        let notifyOnFailed = defaults.object(forKey: "notifyOnFailed") as? Bool ?? true

        let filtered = transitions.filter { transition in
            // Skip notifications for the currently viewed session
            if transition.sessionId == currentlyViewedSessionId { return false }

            switch transition.toState {
            case .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback:
                return notifyOnNeedsInput
            case .completed:
                return notifyOnComplete
            case .failed:
                return notifyOnFailed
            default:
                return false
            }
        }

        guard !filtered.isEmpty else { return }

        // Batch cap: if 4+ transitions, post a single summary
        if filtered.count >= 4 {
            await postSummaryNotification(count: filtered.count)
            return
        }

        for transition in filtered {
            await postNotification(for: transition)
        }
    }

    private func postNotification(for transition: NotifiableTransition) async {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: transition)
        content.body = notificationBody(for: transition)
        content.sound = UNNotificationSound(named: UNNotificationSoundName("jools-chime.caf"))
        content.threadIdentifier = "session-\(transition.sessionId)"
        content.categoryIdentifier = notificationCategory(for: transition.toState)
        content.interruptionLevel = interruptionLevel(for: transition.toState)
        content.userInfo = [
            "sessionId": transition.sessionId,
            "state": transition.toState.rawValue,
        ]

        let identifier = "jools-\(transition.sessionId)-\(transition.toState.rawValue)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Posted notification: \(identifier)")
        } catch {
            logger.error("Failed to post notification: \(error.localizedDescription)")
        }
    }

    private func postSummaryNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Jools"
        content.body = "\(count) sessions need your attention."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("jools-chime.caf"))
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["summary": true]

        let request = UNNotificationRequest(
            identifier: "jools-summary-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Posted summary notification for \(count) sessions")
        } catch {
            logger.error("Failed to post summary notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Categories

    private func registerCategories() {
        let reviewAction = UNNotificationAction(
            identifier: "REVIEW",
            title: "Review",
            options: [.foreground]
        )
        let viewChangesAction = UNNotificationAction(
            identifier: "VIEW_CHANGES",
            title: "View Changes",
            options: [.foreground]
        )
        let inspectAction = UNNotificationAction(
            identifier: "INSPECT",
            title: "Inspect",
            options: [.foreground]
        )

        let needsActionCategory = UNNotificationCategory(
            identifier: "SESSION_NEEDS_ACTION",
            actions: [reviewAction],
            intentIdentifiers: [],
            options: []
        )
        let completedCategory = UNNotificationCategory(
            identifier: "SESSION_COMPLETED",
            actions: [viewChangesAction],
            intentIdentifiers: [],
            options: []
        )
        let failedCategory = UNNotificationCategory(
            identifier: "SESSION_FAILED",
            actions: [inspectAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            needsActionCategory,
            completedCategory,
            failedCategory,
        ])
    }

    // MARK: - Content Helpers

    private func notificationTitle(for transition: NotifiableTransition) -> String {
        switch transition.toState {
        case .awaitingPlanApproval: return "Plan approval needed"
        case .awaitingUserInput, .awaitingUserFeedback: return "Jules needs your input"
        case .completed: return "Session complete"
        case .failed: return "Session failed"
        default: return "Session update"
        }
    }

    private func notificationBody(for transition: NotifiableTransition) -> String {
        let name = transition.repoName ?? transition.sessionTitle
        switch transition.toState {
        case .awaitingPlanApproval:
            return "\(name) is waiting for approval before it continues."
        case .awaitingUserInput, .awaitingUserFeedback:
            return "\(name) paused until you respond in chat."
        case .completed:
            return "\"\(transition.sessionTitle)\" finished successfully."
        case .failed:
            return "\(name) hit an error and needs inspection."
        default:
            return "\(name) has been updated."
        }
    }

    private func notificationCategory(for state: SessionState) -> String {
        switch state {
        case .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback: return "SESSION_NEEDS_ACTION"
        case .completed: return "SESSION_COMPLETED"
        case .failed: return "SESSION_FAILED"
        default: return ""
        }
    }

    private func interruptionLevel(for state: SessionState) -> UNNotificationInterruptionLevel {
        switch state {
        case .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback: return .timeSensitive
        case .completed, .failed: return .active
        default: return .passive
        }
    }

    // MARK: - Cleanup

    /// Call on sign-out to clear all notification state.
    func clearAllState() async {
        await stateTracker.clearAll()
        pendingSessionId = nil
        currentlyViewedSessionId = nil
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        logger.info("Cleared all notification state")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let joolsShouldShowNotificationPrimer = Notification.Name("joolsShouldShowNotificationPrimer")
}
