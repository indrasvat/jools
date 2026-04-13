import SwiftUI
import SwiftData
import JoolsKit

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
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .home
    @State private var deepLinkedSession: SessionEntity?
    @State private var showNotificationPrimer = false

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
        .fullScreenCover(item: $deepLinkedSession) { session in
            NavigationStack {
                ChatView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                deepLinkedSession = nil
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
            }
            .environmentObject(dependencies)
        }
        .sheet(isPresented: $showNotificationPrimer) {
            NotificationPermissionPrimer(
                onEnable: {
                    Task {
                        await dependencies.notificationManager?.requestAuthorization()
                        await dependencies.notificationManager?.postQueuedTransitions()
                    }
                    showNotificationPrimer = false
                },
                onSkip: {
                    Task {
                        await dependencies.notificationManager?.stateTracker
                            .recordPrimerDismissal()
                    }
                    showNotificationPrimer = false
                }
            )
            .presentationDetents([.medium])
        }
        .onReceive(NotificationCenter.default.publisher(for: .joolsShouldShowNotificationPrimer)) { _ in
            showNotificationPrimer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .joolsNotificationTapped)) { notification in
            if let sessionId = notification.userInfo?["sessionId"] as? String {
                NotificationBridge.shared.pendingSessionId = nil
                Task { await navigateToSession(id: sessionId) }
            } else if let tab = notification.userInfo?["tab"] as? String, tab == "sessions" {
                NotificationBridge.shared.pendingTab = nil
                selectedTab = .sessions
            }
        }
        .onAppear {
            // Cold-launch: the notification tap may have fired before
            // this view existed. Consume any pending bridge state.
            if let sessionId = NotificationBridge.shared.pendingSessionId {
                NotificationBridge.shared.pendingSessionId = nil
                Task { await navigateToSession(id: sessionId) }
            }
        }
    }

    /// Fetch a session by ID (local SwiftData first, then API) and
    /// present its ChatView as a full-screen cover.
    private func navigateToSession(id: String) async {
        // Try local first
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            deepLinkedSession = existing
            return
        }

        // Fetch from API, create entity
        do {
            let dto = try await dependencies.apiClient.getSession(id: id)
            let entity = SessionEntity(from: dto)
            modelContext.insert(entity)
            try modelContext.save()
            deepLinkedSession = entity
        } catch {
            // Session was deleted or auth expired — silently fail
        }
    }

    /// Called by NotificationManager when the primer should be shown.
    func presentNotificationPrimer() {
        showNotificationPrimer = true
    }
}

#Preview {
    RootView()
        .environmentObject(AppDependency())
        .environmentObject(ThemeSettings())
}
