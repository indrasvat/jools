import SwiftUI
import SwiftData

/// Main entry point for the Jools iOS app
@main
struct JoolsApp: App {
    @StateObject private var dependencies = AppDependency()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies)
                .modelContainer(dependencies.modelContainer)
        }
    }
}
