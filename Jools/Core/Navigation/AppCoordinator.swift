import SwiftUI
import Observation

/// Navigation routes for the app
enum Route: Hashable {
    // Auth
    case onboarding

    // Main
    case dashboard
    case sourceDetail(sourceId: String)
    case createSession(sourceId: String)
    case sessionDetail(sessionId: String)
    case chat(sessionId: String)
    case planReview(sessionId: String, activityId: String)

    // Settings
    case settings
    case settingsAccount
    case settingsAppearance
    case settingsNotifications
    case settingsAbout

    // Utility
    case webView(url: URL, title: String)
}

/// Coordinates navigation throughout the app
@Observable
@MainActor
final class AppCoordinator {
    // MARK: - Properties

    var navigationPath = NavigationPath()
    var presentedSheet: Route?
    var presentedFullScreen: Route?

    // MARK: - Navigation

    func push(_ route: Route) {
        navigationPath.append(route)
    }

    func pop() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    func popToRoot() {
        navigationPath.removeLast(navigationPath.count)
    }

    func present(_ route: Route, style: PresentationStyle = .sheet) {
        switch style {
        case .sheet:
            presentedSheet = route
        case .fullScreen:
            presentedFullScreen = route
        }
    }

    func dismiss() {
        presentedSheet = nil
        presentedFullScreen = nil
    }
}

enum PresentationStyle {
    case sheet
    case fullScreen
}
