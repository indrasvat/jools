import UIKit
import UserNotifications
import BackgroundTasks

/// App delegate for notification handling and background task registration.
/// Must be set as the UNUserNotificationCenter delegate before the app
/// finishes launching to catch cold-launch notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundSessionChecker.register()
        BackgroundSessionChecker.scheduleNext()
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification arrives while the app is in the foreground.
    /// Suppress the banner if the user is already viewing that session.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let sessionId = userInfo["sessionId"] as? String
        let viewedId = await MainActor.run { NotificationBridge.shared.currentlyViewedSessionId }
        if let sessionId, sessionId == viewedId {
            return []
        }
        return [.banner, .sound, .badge]
    }

    /// Called when the user taps a notification or a notification action button.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        if let sessionId = userInfo["sessionId"] as? String {
            await MainActor.run { NotificationBridge.shared.pendingSessionId = sessionId }
        } else if let action = userInfo["action"] as? String, action == "openSessions" {
            await MainActor.run { NotificationBridge.shared.pendingTab = "sessions" }
        }
        // Summary notifications without a session ID or action just
        // foreground the app (default iOS behavior).
    }
}

/// Bridges notification state between AppDelegate (UIKit) and the SwiftUI
/// world. AppDelegate can't access @EnvironmentObject, so this singleton
/// carries the currently viewed session ID (for foreground suppression)
/// and the pending deep-link session ID (for notification taps).
///
/// NotificationManager writes `currentlyViewedSessionId` here whenever
/// ChatView sets it. MainTabView observes `pendingSessionId` changes
/// via Foundation NotificationCenter.
@MainActor
final class NotificationBridge {
    static let shared = NotificationBridge()

    /// The session ID currently displayed in ChatView. Set by
    /// NotificationManager when ChatView appears/disappears.
    var currentlyViewedSessionId: String?

    /// Set by AppDelegate for summary notification taps to switch tab.
    var pendingTab: String? {
        didSet {
            guard let tab = pendingTab else { return }
            NotificationCenter.default.post(
                name: .joolsNotificationTapped,
                object: nil,
                userInfo: ["tab": tab]
            )
        }
    }

    /// Set by AppDelegate when a notification is tapped. MainTabView
    /// observes changes via Foundation NotificationCenter.
    var pendingSessionId: String? {
        didSet {
            guard let id = pendingSessionId else { return }
            NotificationCenter.default.post(
                name: .joolsNotificationTapped,
                object: nil,
                userInfo: ["sessionId": id]
            )
        }
    }
}

extension Notification.Name {
    static let joolsNotificationTapped = Notification.Name("joolsNotificationTapped")
}
