import Foundation
import BackgroundTasks
import UserNotifications
import JoolsKit
import os

/// Handles BGAppRefreshTask to poll the Jules API for session state
/// changes while the app is suspended. Posts local notifications for
/// notifiable transitions (plan approval needed, input needed,
/// completed, failed).
enum BackgroundSessionChecker {
    static let taskIdentifier = "com.indrasvat.jools.session-check"
    private static let logger = Logger(subsystem: "com.indrasvat.jools", category: "BackgroundSessionChecker")

    /// Register the background task handler. Must be called in
    /// `application(_:didFinishLaunchingWithOptions:)` before the
    /// method returns.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleAppRefresh(task: refreshTask)
        }
        logger.info("Registered background task: \(taskIdentifier)")
    }

    /// Schedule the next background refresh. Call on launch and after
    /// each background task completes.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled next background refresh")
        } catch {
            // .notPermitted if entitlement missing, .unavailable on simulator
            logger.warning("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the NEXT refresh immediately so we keep getting woken up.
        scheduleNext()

        // BGAppRefreshTask is not Sendable, and Swift 6 strict concurrency
        // rejects capturing it in a Task closure. Use @Sendable + unchecked
        // nonisolated wrapper to satisfy the compiler. The BGTask framework
        // guarantees the handler runs on a serial queue, making this safe.
        let wrapper = UncheckedSendableBox(task)

        let fetchTask = Task { @Sendable in
            do {
                try await performCheck()
                wrapper.value.setTaskCompleted(success: true)
            } catch {
                logger.error("Background check failed: \(error.localizedDescription)")
                wrapper.value.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            fetchTask.cancel()
            wrapper.value.setTaskCompleted(success: false)
        }
    }

    private static func performCheck() async throws {
        // Create a lightweight API client from keychain.
        // kSecAttrAccessibleAfterFirstUnlock means this works even when
        // the device is locked (as long as it's been unlocked once since
        // reboot). If the keychain read fails (e.g. device never unlocked
        // since reboot), we bail gracefully without triggering sign-out.
        let keychain = KeychainManager(service: "com.jools.app")
        guard keychain.hasAPIKey() else {
            logger.info("No API key in keychain — skipping background check")
            return
        }

        // Check authorization BEFORE consuming transitions from the
        // state tracker. processTransitions mutates persisted state, so
        // running it when we can't post burns the transition silently.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            logger.info("Notifications not authorized — skipping background check entirely")
            return
        }

        let apiClient = APIClient(keychain: keychain)
        let sessions = try await apiClient.listAllSessions(pageSize: 100)

        let stateTracker = SessionStateTracker.shared
        let transitions = await stateTracker.processTransitions(sessions)

        guard !transitions.isEmpty else {
            logger.debug("No notifiable transitions in background check")
            return
        }

        // Read toggles
        let defaults = UserDefaults.standard
        let notifyOnComplete = defaults.object(forKey: "notifyOnComplete") as? Bool ?? true
        let notifyOnNeedsInput = defaults.object(forKey: "notifyOnNeedsInput") as? Bool ?? true
        let notifyOnFailed = defaults.object(forKey: "notifyOnFailed") as? Bool ?? true

        let filtered = transitions.filter { t in
            switch t.toState {
            case .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback: return notifyOnNeedsInput
            case .completed: return notifyOnComplete
            case .failed: return notifyOnFailed
            default: return false
            }
        }

        guard !filtered.isEmpty else { return }

        // Batch cap: 1 summary if 4+
        if filtered.count >= 4 {
            let content = UNMutableNotificationContent()
            content.title = "Jools"
            content.body = "\(filtered.count) sessions need your attention."
            content.sound = UNNotificationSound(named: UNNotificationSoundName("jools-chime.caf"))
            content.interruptionLevel = .active
            let request = UNNotificationRequest(
                identifier: "jools-bg-summary",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
            logger.info("Posted background summary notification for \(filtered.count) sessions")
            return
        }

        for transition in filtered {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle(for: transition)
            content.body = notificationBody(for: transition)
            content.sound = UNNotificationSound(named: UNNotificationSoundName("jools-chime.caf"))
            content.threadIdentifier = "session-\(transition.sessionId)"
            content.categoryIdentifier = notificationCategory(for: transition.toState)
            content.interruptionLevel = interruptionLevel(for: transition.toState)
            content.userInfo = ["sessionId": transition.sessionId, "state": transition.toState.rawValue]

            let identifier = "jools-\(transition.sessionId)-\(transition.toState.rawValue)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            logger.info("Posted background notification: \(identifier)")
        }
    }

    // MARK: - Content Helpers (duplicated from NotificationManager for background context)

    private static func notificationTitle(for transition: NotifiableTransition) -> String {
        switch transition.toState {
        case .awaitingPlanApproval: return "Plan approval needed"
        case .awaitingUserInput, .awaitingUserFeedback: return "Jules needs your input"
        case .completed: return "Session complete"
        case .failed: return "Session failed"
        default: return "Session update"
        }
    }

    private static func notificationBody(for transition: NotifiableTransition) -> String {
        let name = transition.repoName ?? transition.sessionTitle
        switch transition.toState {
        case .awaitingPlanApproval: return "\(name) is waiting for approval before it continues."
        case .awaitingUserInput, .awaitingUserFeedback: return "\(name) paused until you respond in chat."
        case .completed: return "\"\(transition.sessionTitle)\" finished successfully."
        case .failed: return "\(name) hit an error and needs inspection."
        default: return "\(name) has been updated."
        }
    }

    private static func notificationCategory(for state: SessionState) -> String {
        switch state {
        case .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback: return "SESSION_NEEDS_ACTION"
        case .completed: return "SESSION_COMPLETED"
        case .failed: return "SESSION_FAILED"
        default: return ""
        }
    }

    private static func interruptionLevel(for state: SessionState) -> UNNotificationInterruptionLevel {
        switch state {
        case .awaitingPlanApproval, .awaitingUserInput, .awaitingUserFeedback: return .timeSensitive
        case .completed, .failed: return .active
        default: return .passive
        }
    }
}

/// Wraps a non-Sendable value for use in `@Sendable` closures where
/// the caller guarantees thread-safety externally (e.g. BGTask handler
/// runs on a serial queue).
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
