import SwiftUI

/// Root view that handles authentication state and main navigation
struct RootView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @State private var coordinator = AppCoordinator()

    var body: some View {
        Group {
            if dependencies.isAuthenticated {
                MainTabView()
                    .environment(coordinator)
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: dependencies.isAuthenticated)
        // Note: scenePhase listener removed. ChatView already handles
        // foreground/background transitions for the polling service —
        // having BOTH RootView and ChatView call enterForeground()
        // restarted the polling loop twice on a single app activation,
        // and on background the redundant enterBackground() didn't
        // cause harm but added confusion. Centralizing in ChatView
        // (which is the only screen that actually needs the polling
        // service to react to scene phase) is cleaner. (Codex review.)
    }
}

/// Main tab bar view for authenticated users
struct MainTabView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home
        case sessions
        case settings

        var title: String {
            switch self {
            case .home: return "Home"
            case .sessions: return "Sessions"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .home: return "square.grid.2x2"
            case .sessions: return "bubble.left.and.bubble.right"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(Tab.home.title, systemImage: Tab.home.icon)
                }
                .tag(Tab.home)
                .accessibilityIdentifier("tab.home")

            SessionsListView()
                .tabItem {
                    Label(Tab.sessions.title, systemImage: Tab.sessions.icon)
                }
                .tag(Tab.sessions)
                .accessibilityIdentifier("tab.sessions")

            SettingsView()
                .tabItem {
                    Label(Tab.settings.title, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
                .accessibilityIdentifier("tab.settings")
        }
        .tint(.joolsAccent)
    }
}

#Preview {
    RootView()
        .environmentObject(AppDependency())
        .environmentObject(ThemeSettings())
}
