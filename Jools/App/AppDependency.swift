import SwiftUI
import SwiftData
import JoolsKit

/// Central dependency container for the Jools app
@MainActor
final class AppDependency: ObservableObject {
    // MARK: - Services

    let keychainManager: KeychainManager
    let apiClient: APIClient
    let pollingService: PollingService
    let modelContainer: ModelContainer
    let notificationManager: NotificationManager?
    let isUITestMode: Bool

    // MARK: - State

    @Published var isAuthenticated: Bool = false

    // MARK: - Initialization

    init() {
        let environment = ProcessInfo.processInfo.environment
        self.isUITestMode = environment["JOOLS_UI_TEST_MODE"] == "1"
        let shouldAuthenticateForUITest = environment["JOOLS_UI_TEST_AUTHENTICATED"] != "0"

        // Initialize keychain manager
        self.keychainManager = KeychainManager(
            service: isUITestMode ? "com.indrasvat.jools.ui-tests" : "com.jools.app"
        )

        // Initialize API client
        self.apiClient = APIClient(keychain: keychainManager)

        // Initialize polling service
        self.pollingService = PollingService(api: apiClient)

        // Initialize notification manager (skip in UI test mode)
        self.notificationManager = isUITestMode ? nil : NotificationManager(apiClient: apiClient)

        // Initialize SwiftData container
        do {
            let schema = Schema([
                SessionEntity.self,
                SourceEntity.self,
                ActivityEntity.self,
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: isUITestMode
            )
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Check if user is authenticated
        if isUITestMode {
            self.isAuthenticated = shouldAuthenticateForUITest
            if shouldAuthenticateForUITest {
                seedUITestData(scenario: environment["JOOLS_UI_TEST_SCENARIO"] ?? "running-session")
            }
        } else {
            self.isAuthenticated = keychainManager.hasAPIKey()
        }
    }

    // MARK: - Authentication

    func authenticate(with apiKey: String) async throws -> Bool {
        // Save the API key
        try keychainManager.saveAPIKey(apiKey)

        // Validate it
        let isValid = try await apiClient.validateAPIKey()

        if isValid {
            await MainActor.run {
                self.isAuthenticated = true
            }
        } else {
            // Remove invalid key
            try? keychainManager.deleteAPIKey()
        }

        return isValid
    }

    func signOut() throws {
        try keychainManager.deleteAPIKey()
        isAuthenticated = false
        pollingService.stopPolling()
        // Synchronous cleanup of notification state to prevent stale
        // data leaking across account switches. The async clearAllState
        // handles UNUserNotificationCenter calls; we also clear the
        // UserDefaults-backed state tracker synchronously here.
        notificationManager?.pendingSessionId = nil
        notificationManager?.currentlyViewedSessionId = nil
        UserDefaults.standard.removeObject(forKey: "jools.stateTracker.stateMap")
        UserDefaults.standard.removeObject(forKey: "jools.stateTracker.hasSeeded")
        UserDefaults.standard.removeObject(forKey: "jools.stateTracker.pendingTransitions")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Wipe every locally cached `SessionEntity`, `SourceEntity`, and
    /// `ActivityEntity` from SwiftData and then sign out. Used by the
    /// "Delete All Data" destructive action in Settings — without this,
    /// signing out and reauthenticating with a different API key would
    /// leave the previous account's sessions visible (a real privacy
    /// hazard on shared devices, flagged in PR #1 review).
    func deleteAllLocalData() throws {
        let context = modelContainer.mainContext

        try context.delete(model: ActivityEntity.self)
        try context.delete(model: SessionEntity.self)
        try context.delete(model: SourceEntity.self)
        try context.save()

        try signOut()
    }

    // MARK: - UI Testing

    private func seedUITestData(scenario: String) {
        let context = modelContainer.mainContext

        let sources = [
            SourceEntity(
                id: "github/indrasvat/hews",
                name: "hews",
                owner: "indrasvat",
                repo: "hews"
            ),
            SourceEntity(
                id: "github/indrasvat/namefix",
                name: "namefix",
                owner: "indrasvat",
                repo: "namefix"
            ),
        ]

        for source in sources {
            context.insert(source)
        }

        let primaryTitle: String
        let primaryState: SessionState

        switch scenario {
        case "stale-session":
            primaryTitle = "UI Test Stale Session"
            primaryState = .inProgress
        default:
            primaryTitle = "UI Test Running Session"
            primaryState = .awaitingPlanApproval
        }

        let session = SessionEntity(
            id: "ui-session-\(scenario)",
            title: primaryTitle,
            prompt: "Validate the session recovery UI",
            state: primaryState,
            sourceId: "github/indrasvat/hews",
            sourceBranch: "main",
            automationMode: .autoCreatePR,
            requirePlanApproval: true,
            createdAt: Date().addingTimeInterval(-600),
            updatedAt: Date().addingTimeInterval(-30)
        )
        context.insert(session)

        let secondarySession = SessionEntity(
            id: "ui-session-awaiting-input-\(scenario)",
            title: "UI Test Awaiting Input Session",
            prompt: "Validate the home attention stack",
            state: .awaitingUserInput,
            sourceId: "github/indrasvat/namefix",
            sourceBranch: "main",
            automationMode: .autoCreatePR,
            requirePlanApproval: false,
            createdAt: Date().addingTimeInterval(-2_400),
            updatedAt: Date().addingTimeInterval(-120)
        )
        context.insert(secondarySession)

        let activities = uiTestActivities(for: scenario)
        for activity in activities {
            activity.session = session
            context.insert(activity)
        }

        try? context.save()
    }

    private func uiTestActivities(for scenario: String) -> [ActivityEntity] {
        let planContent = ActivityContentDTO(
            plan: PlanDTO(
                id: "plan-ui",
                steps: [
                    PlanStepDTO(
                        id: "step-1",
                        title: "Inspect the model layer",
                        description: "Check the session detail view and keep the cached timeline visible while syncing.",
                        status: "COMPLETED",
                        index: 1
                    ),
                    PlanStepDTO(
                        id: "step-2",
                        title: "Provide the summary to the user",
                        description: "Reply directly in chat once the analysis is ready.",
                        status: "IN_PROGRESS",
                        index: 2
                    )
                ]
            )
        )

        let progressContent = ActivityContentDTO(
            progress: "Provide the summary to the user",
            progressTitle: "Provide the summary to the user",
            progressDescription: "Reply directly in chat with the latest findings."
        )

        let agentContent = ActivityContentDTO(
            message: scenario == "stale-session"
                ? "The cached timeline should remain visible while the app attempts to recover."
                : "The session view now shows the latest working step instead of a generic loading banner."
        )

        return [
            ActivityEntity(
                id: "ui-user-message-\(scenario)",
                type: .userMessaged,
                createdAt: Date().addingTimeInterval(-540),
                contentJSON: (try? JSONEncoder().encode(ActivityContentDTO(message: "Can you summarize the repo status?"))) ?? Data()
            ),
            ActivityEntity(
                id: "ui-plan-\(scenario)",
                type: .planGenerated,
                createdAt: Date().addingTimeInterval(-420),
                contentJSON: (try? JSONEncoder().encode(planContent)) ?? Data()
            ),
            ActivityEntity(
                id: "ui-progress-\(scenario)",
                type: .progressUpdated,
                createdAt: Date().addingTimeInterval(-120),
                contentJSON: (try? JSONEncoder().encode(progressContent)) ?? Data()
            ),
            ActivityEntity(
                id: "ui-agent-\(scenario)",
                type: .agentMessaged,
                createdAt: Date().addingTimeInterval(-60),
                contentJSON: (try? JSONEncoder().encode(agentContent)) ?? Data()
            )
        ]
    }
}
