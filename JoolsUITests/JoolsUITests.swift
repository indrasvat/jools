import XCTest

final class JoolsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsSuggestedAndScheduledSections() throws {
        let app = makeApp(scenario: "running-session")
        app.launch()

        XCTAssertTrue(app.staticTexts["Needs Attention"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Suggested"].waitForExistence(timeout: 5))

        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 5))
        scrollUntilVisible(
            app.staticTexts["Scheduled"],
            in: homeScroll,
            maxSwipes: 3
        )

        XCTAssertTrue(app.staticTexts["Scheduled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sources"].exists)
    }

    @MainActor
    func testScheduledPresetOpensComposer() throws {
        let app = makeApp(scenario: "running-session")
        app.launch()

        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["Scheduled"], in: homeScroll, maxSwipes: 4)
        let scheduleButton = app.buttons["Schedule"].firstMatch
        scrollUntilVisible(scheduleButton, in: homeScroll, maxSwipes: 4)
        XCTAssertTrue(scheduleButton.waitForExistence(timeout: 5))
        scheduleButton.tap()

        XCTAssertTrue(app.navigationBars["Scheduled Task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Continue in Jules"].exists)
        XCTAssertTrue(app.buttons["scheduled.copyPrompt"].exists)
        XCTAssertTrue(app.buttons["scheduled.continue"].exists)
    }

    @MainActor
    func testSuggestedStartOpensPrefilledSessionComposer() throws {
        let app = makeApp(scenario: "running-session")
        app.launch()

        let startButton = app.buttons["Start"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.navigationBars["New Session"].waitForExistence(timeout: 5))
        let promptField = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(promptField.waitForExistence(timeout: 5))
        XCTAssertFalse((promptField.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    func testRunningSessionScreenShowsRecoveryChrome() throws {
        let app = makeApp(scenario: "running-session")
        app.launch()

        openSessionsTab(in: app)

        openSession(named: "UI Test Running Session", in: app)

        XCTAssertTrue(app.staticTexts["Jules is working"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Provide the summary to the user"].waitForExistence(timeout: 10))
        // Note: previous versions of this test asserted the presence
        // of a `chat.scroll` container via `app.descendants(matching:
        // .any)["chat.scroll"].firstMatch.exists`, which walks the
        // entire accessibility tree. On GitHub's macos-15 runners
        // that whole-tree query regularly blew the snapshot timeout
        // (~30 s), wedging the simulator and cascading into
        // "Failed to terminate" / "Failed to launch" errors in
        // every subsequent test. The presence of the chat list is
        // already implied by the specific `chat.input`, `chat.send`,
        // and `chat.refresh` assertions below, so the broad query
        // added no independent coverage.
        XCTAssertTrue(app.textFields["chat.input"].waitForExistence(timeout: 5) || app.textViews["chat.input"].exists)
        XCTAssertTrue(app.buttons["chat.send"].exists)
        XCTAssertTrue(app.buttons["chat.refresh"].exists)
        XCTAssertTrue(
            staticText(containing: "Updated", in: app).waitForExistence(timeout: 5) ||
            staticText(containing: "Pull to refresh", in: app).exists
        )
    }

    // Note: `testStartingSessionUsesTimelineDerivedNeedsInputState`
    // was removed. It asserted that a session with API state
    // `.unspecified` plus an agent question in the timeline should
    // render the "Jules needs your input" banner — behavior powered by
    // the content-scanning heuristic that guessed needs-input from
    // message text ("let me know", "could you clarify", etc.). That
    // heuristic was explicitly removed ("use the proper API statuses")
    // because it produced false positives on unrelated closer text
    // like "have a great day, let me know if anything breaks". The
    // forward-compatible `.unspecified` → "Starting" rendering is
    // covered by JoolsKit unit tests and by the ResolvedSessionState
    // humanize path, so there's nothing left for a UI test to cover
    // in that scenario without reintroducing the heuristic.

    @MainActor
    func testStaleSessionShowsRetryAction() throws {
        let app = makeApp(
            scenario: "stale-session",
            syncState: "stale"
        )
        app.launch()

        openSessionsTab(in: app)

        openSession(named: "UI Test Stale Session", in: app)

        XCTAssertTrue(staticText(containing: "Showing the last synced timeline", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Tap to retry"].exists ||
            app.buttons["chat.retry"].exists ||
            app.staticTexts["Tap to retry"].exists
        )
    }

    @MainActor
    func testSessionScreenSurvivesBackgroundForeground() throws {
        let app = makeApp(scenario: "running-session")
        app.launch()

        openSessionsTab(in: app)
        openSession(named: "UI Test Running Session", in: app)

        XCTAssertTrue(app.staticTexts["Provide the summary to the user"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()

        // After `activate()` the accessibility snapshot isn't
        // guaranteed to be fresh immediately — on slow CI runners
        // the first `.exists` call can return false while the
        // window server is still repainting. `.waitForExistence`
        // polls with XCUITest's own retry loop, which is what we
        // want here. The previous `.exists` form flaked on one
        // macos-15 run and tore down the entire test suite via
        // simulator state corruption when the test timed out.
        XCTAssertTrue(
            app.staticTexts["Provide the summary to the user"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["chat.refresh"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingSupportsLightMode() throws {
        let app = makeApp(
            scenario: "running-session",
            authenticated: false,
            colorScheme: "light"
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Jools"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect to Jules"].exists)
        XCTAssertTrue(app.buttons["I already have a key"].exists)
    }

    @MainActor
    func testHomeSupportsDarkMode() throws {
        let app = makeApp(
            scenario: "running-session",
            colorScheme: "dark"
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Needs Attention"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Suggested"].exists)
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
    }

    @MainActor
    func testAppearancePickerSwitchesSelectionLive() throws {
        let app = makeApp(scenario: "running-session")
        app.launchEnvironment["JOOLS_UI_TEST_SETTINGS_DESTINATION"] = "appearance"
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let navBar = app.navigationBars["Appearance"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 5))

        let lightButton = app.segmentedControls.buttons["Light"].firstMatch
        let darkButton = app.segmentedControls.buttons["Dark"].firstMatch
        XCTAssertTrue(lightButton.waitForExistence(timeout: 5))
        XCTAssertTrue(darkButton.exists)

        lightButton.tap()
        XCTAssertTrue(lightButton.isSelected)

        darkButton.tap()
        XCTAssertTrue(darkButton.isSelected)
    }

    @MainActor
    private func makeApp(
        scenario: String,
        syncState: String? = nil,
        authenticated: Bool = true,
        colorScheme: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOOLS_UI_TEST_MODE"] = "1"
        app.launchEnvironment["JOOLS_UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["JOOLS_UI_TEST_AUTHENTICATED"] = authenticated ? "1" : "0"
        // Disable SwiftUI animations during UI tests so element waits
        // resolve as soon as the view is in place rather than after
        // the next animation frame. Halves end-to-end test runtime.
        app.launchEnvironment["JOOLS_UI_TEST_DISABLE_ANIMATIONS"] = "1"
        if let syncState {
            app.launchEnvironment["JOOLS_UI_TEST_SYNC_STATE"] = syncState
        }
        if let colorScheme {
            app.launchEnvironment["JOOLS_UI_TEST_COLOR_SCHEME"] = colorScheme
        }
        return app
    }

    @MainActor
    private func openSessionsTab(in app: XCUIApplication) {
        let tabButton = app.tabBars.buttons["tab.sessions"].firstMatch
        if tabButton.waitForExistence(timeout: 5) {
            tabButton.tap()
            return
        }

        let titledTabButton = app.tabBars.buttons["Sessions"].firstMatch
        XCTAssertTrue(titledTabButton.waitForExistence(timeout: 5))
        titledTabButton.tap()
    }

    @MainActor
    private func openSession(named title: String, in app: XCUIApplication) {
        let titleText = app.staticTexts[title].firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 5))

        let containingCell = app.cells.containing(.staticText, identifier: title).firstMatch
        if containingCell.exists {
            containingCell.tap()
            return
        }

        titleText.tap()
    }

    @MainActor
    private func staticText(containing substring: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    @MainActor
    private func scrollUntilVisible(_ element: XCUIElement, in scrollView: XCUIElement, maxSwipes: Int) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            scrollView.swipeUp()
            swipes += 1
        }
    }
}
