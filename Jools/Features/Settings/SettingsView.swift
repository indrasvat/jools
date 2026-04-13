import SwiftUI
import UserNotifications

/// Settings view
struct SettingsView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @State private var showSignOutAlert = false
    @State private var showDeleteDataAlert = false
    @State private var path = NavigationPath()

    private var initialDestination: SettingsDestination? {
        guard dependencies.isUITestMode else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment["JOOLS_UI_TEST_SETTINGS_DESTINATION"] else { return nil }
        return SettingsDestination(rawValue: rawValue)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Account Section
                Section("Account") {
                    HStack {
                        Label("API Key", systemImage: "key")
                        Spacer()
                        Text("••••••••")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("settings.row.apiKey")

                    Link(destination: URL(string: "https://jules.google.com/settings")!) {
                        HStack {
                            Label("Plan & Usage", systemImage: "crown")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.row.planUsage")
                }

                // Preferences Section
                Section("Preferences") {
                    NavigationLink(value: SettingsDestination.appearance) {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                    .accessibilityIdentifier("settings.row.appearance")

                    NavigationLink(value: SettingsDestination.notifications) {
                        Label("Notifications", systemImage: "bell")
                    }
                    .accessibilityIdentifier("settings.row.notifications")
                }

                // About Section
                Section("About") {
                    Link(destination: URL(string: "https://jules.google.com/docs")!) {
                        Label("Jules Documentation", systemImage: "book")
                    }

                    Link(destination: URL(string: "https://jules.google.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                // Build Info Section
                Section("Build Info") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(BuildInfo.fullVersion)
                            .foregroundStyle(.secondary)
                            .font(.joolsCaption)
                    }

                    HStack {
                        Label("Git SHA", systemImage: "number")
                        Spacer()
                        Text(BuildInfo.gitSHA)
                            .foregroundStyle(.secondary)
                            .font(.system(.caption, design: .monospaced))
                    }

                    HStack {
                        Label("Branch", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text(BuildInfo.gitBranch)
                            .foregroundStyle(.secondary)
                            .font(.joolsCaption)
                    }

                    HStack {
                        Label("Built", systemImage: "clock")
                        Spacer()
                        Text(BuildInfo.buildDate)
                            .foregroundStyle(.secondary)
                            .font(.joolsCaption)
                    }
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showDeleteDataAlert = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                }

                Section {
                    MadeWithJoolsFooter(style: .list)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .appearance:
                    AppearanceSettingsView()
                case .notifications:
                    NotificationSettingsView()
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete All Data", isPresented: $showDeleteDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will delete all local data and sign you out. This action cannot be undone.")
            }
            .onAppear {
                guard let initialDestination, path.isEmpty else { return }
                path.append(initialDestination)
            }
        }
    }

    private func signOut() {
        HapticManager.shared.warning()
        try? dependencies.signOut()
    }

    private func deleteAllData() {
        HapticManager.shared.heavyImpact()
        // Wipe every locally cached session/source/activity AND drop
        // the API key in one shot. Without this, signing back in with
        // a different account would leave the previous account's
        // sessions visible. (PR #1 Codex review.)
        do {
            try dependencies.deleteAllLocalData()
        } catch {
            // Best-effort fallback: at minimum drop the API key so the
            // user lands back on Onboarding.
            try? dependencies.signOut()
        }
    }
}

private enum SettingsDestination: String, Hashable {
    case appearance
    case notifications
}

// MARK: - Settings Sub-Views

struct AppearanceSettingsView: View {
    @EnvironmentObject private var themeSettings: ThemeSettings

    var body: some View {
        List {
            Section("Theme") {
                Picker(
                    "Color Scheme",
                    selection: Binding(
                        get: { themeSettings.colorScheme },
                        set: { themeSettings.update($0) }
                    )
                ) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.title)
                            .tag(scheme)
                            // Per-segment identifiers so axe / XCUITest
                            // can target the segments by id rather than
                            // raw coordinates. SwiftUI doesn't expose
                            // the segments as separate AX elements, but
                            // these still get picked up via the tag's
                            // accessibility metadata.
                            .accessibilityIdentifier("appearance.option.\(scheme.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance.picker")

                if themeSettings.isOverriddenForTesting {
                    Text("Theme is currently overridden by the UI test environment.")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                MadeWithJoolsFooter(style: .list)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Appearance")
    }
}

struct NotificationSettingsView: View {
    @AppStorage("notifyOnComplete") private var notifyOnComplete = true
    @AppStorage("notifyOnNeedsInput") private var notifyOnNeedsInput = true
    @AppStorage("notifyOnFailed") private var notifyOnFailed = true
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: permissionIcon)
                        .foregroundStyle(permissionColor)
                    Text(permissionLabel)
                    Spacer()
                    if authorizationStatus == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.joolsCaption)
                    }
                }
            } header: {
                Text("Permission")
            } footer: {
                if authorizationStatus == .denied {
                    Text("Notifications are disabled in system settings. Tap \"Open Settings\" to enable them.")
                }
            }

            Section {
                Toggle("Plan Approvals & Input", isOn: $notifyOnNeedsInput)
                Toggle("Session Completed", isOn: $notifyOnComplete)
                Toggle("Session Failed", isOn: $notifyOnFailed)
            } header: {
                Text("Notify me when...")
            } footer: {
                Text("These preferences apply when notifications are enabled in system settings.")
            }

            Section {
                MadeWithJoolsFooter(style: .list)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Notifications")
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    private var permissionIcon: String {
        switch authorizationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .provisional: return "circle.dashed"
        default: return "circle"
        }
    }

    private var permissionColor: Color {
        switch authorizationStatus {
        case .authorized: return .joolsSuccess
        case .denied: return .joolsFailed
        case .provisional: return .joolsAwaiting
        default: return .secondary
        }
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case .authorized: return "Enabled"
        case .denied: return "Disabled"
        case .provisional: return "Provisional"
        default: return "Not asked yet"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppDependency())
        .environmentObject(ThemeSettings())
}
