import SwiftUI
import SwiftData
import UIKit

/// Main entry point for the Jools iOS app
@main
struct JoolsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var dependencies = AppDependency()
    @StateObject private var themeSettings = ThemeSettings()

    init() {
        // UI tests run dozens of cold app launches in a row. SwiftUI's
        // default animations add ~0.5-2s of dead time per interaction
        // for tests that are mostly waiting on element existence. We
        // honour `JOOLS_UI_TEST_DISABLE_ANIMATIONS=1` (set by the UI
        // test bundle) to skip them entirely. The flag is a no-op for
        // real users.
        if ProcessInfo.processInfo.environment["JOOLS_UI_TEST_DISABLE_ANIMATIONS"] == "1" {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies)
                .environmentObject(themeSettings)
                .modelContainer(dependencies.modelContainer)
                .preferredColorScheme(themeSettings.preferredColorScheme)
        }
    }
}
