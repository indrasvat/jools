import SwiftUI

/// Settings view
struct SettingsView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @State private var showSignOutAlert = false
    @State private var showDeleteDataAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    HStack {
                        Label("API Key", systemImage: "key")
                        Spacer()
                        Text("••••••••")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Plan", systemImage: "crown")
                        Spacer()
                        Text("Free")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        UsageDetailView()
                    } label: {
                        Label("Daily Usage", systemImage: "chart.bar")
                    }
                }

                // Preferences Section
                Section("Preferences") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }
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
            }
            .navigationTitle("Settings")
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
        }
    }

    private func signOut() {
        HapticManager.shared.warning()
        try? dependencies.signOut()
    }

    private func deleteAllData() {
        HapticManager.shared.heavyImpact()
        // TODO: Clear SwiftData
        try? dependencies.signOut()
    }
}

// MARK: - Placeholder Views

struct UsageDetailView: View {
    var body: some View {
        List {
            Section("Today") {
                HStack {
                    Text("Tasks Used")
                    Spacer()
                    Text("3/15")
                }
                HStack {
                    Text("Concurrent Tasks")
                    Spacer()
                    Text("1/3")
                }
            }

            Section {
                Text("Upgrade to Pro for 100 daily tasks")
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)

                Link("Upgrade Plan", destination: URL(string: "https://jules.google.com/pricing")!)
            }
        }
        .navigationTitle("Usage")
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("colorScheme") private var colorScheme: String = "system"

    var body: some View {
        List {
            Section("Theme") {
                Picker("Color Scheme", selection: $colorScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Appearance")
    }
}

struct NotificationSettingsView: View {
    @AppStorage("notifyOnComplete") private var notifyOnComplete = true
    @AppStorage("notifyOnNeedsInput") private var notifyOnNeedsInput = true

    var body: some View {
        List {
            Section("Session Notifications") {
                Toggle("Session Completed", isOn: $notifyOnComplete)
                Toggle("Needs Your Input", isOn: $notifyOnNeedsInput)
            }
        }
        .navigationTitle("Notifications")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppDependency())
}
