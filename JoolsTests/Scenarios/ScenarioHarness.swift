import Foundation
import SwiftData
import Testing
@testable import Jools
@testable import JoolsKit

/// Orchestrates a scenario test. Wires a real `APIClient` (routed
/// through `ScenarioURLProtocol`), a real in-memory SwiftData
/// `ModelContainer`, a real `PollingService`, and a real
/// `ChatViewModel` — the same pieces the app wires at runtime — then
/// exposes verbs that a scenario can use to step through user
/// actions and assert on observable state.
///
/// Use via:
///
///     @MainActor
///     @Test("Staleness recovery")
///     func stalenessRecovery() async throws {
///         let harness = try ScenarioHarness(sessionId: "s1")
///         harness.responses.fail(with: .timedOut) // first list fails
///         harness.responses.respond(json: activitiesJSON) // second succeeds
///         await harness.loadActivities()
///         try await harness.awaitSyncState(.stale) // after timeout
///         await harness.manualRefresh()
///         try await harness.awaitSyncState(.idle)
///         #expect(harness.session.activities.count == 3)
///     }
@MainActor
final class ScenarioHarness {
    let session: SessionEntity
    let viewModel: ChatViewModel
    let responses: MockResponseQueue

    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let apiClient: APIClient
    let pollingService: PollingService
    private let keychain: KeychainManager
    private let keychainService: String

    /// Build a harness with a seeded session. The session is inserted
    /// into an in-memory `ModelContainer` so activity refresh paths
    /// have a real `SessionEntity` to mutate. `sessionTitle` and
    /// `initialState` are tunable for scenarios that need a specific
    /// starting point.
    init(
        sessionId: String = "test-session-\(UUID().uuidString)",
        sessionTitle: String = "Scenario session",
        initialState: SessionState = .inProgress
    ) throws {
        let schema = Schema([SessionEntity.self, ActivityEntity.self, SourceEntity.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = ModelContext(modelContainer)

        let session = SessionEntity(
            id: sessionId,
            title: sessionTitle,
            prompt: "scenario prompt",
            state: initialState,
            sourceId: "sources/test/scenario",
            sourceBranch: "main",
            automationMode: .unspecified,
            requirePlanApproval: false,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        modelContext.insert(session)
        try modelContext.save()
        self.session = session

        let responses = MockResponseQueue()
        self.responses = responses
        ScenarioURLProtocol.queue = responses

        let urlConfig = URLSessionConfiguration.ephemeral
        urlConfig.protocolClasses = [ScenarioURLProtocol.self]
        let urlSession = URLSession(configuration: urlConfig)

        let keychainService = "com.indrasvat.jools.scenarios.\(UUID().uuidString)"
        let keychain = KeychainManager(service: keychainService)
        try keychain.saveAPIKey("scenario-test-key")
        self.keychain = keychain
        self.keychainService = keychainService

        self.apiClient = APIClient(
            keychain: keychain,
            session: urlSession,
            baseURL: URL(string: "https://example.com/v1alpha/")!
        )
        self.pollingService = PollingService(api: apiClient)

        let viewModel = ChatViewModel()
        viewModel.configure(
            apiClient: apiClient,
            modelContext: modelContext,
            pollingService: pollingService,
            sessionId: sessionId
        )
        self.viewModel = viewModel
    }

    deinit {
        ScenarioURLProtocol.queue = nil
        try? keychain.deleteAPIKey()
    }

    // MARK: - Verbs (called from scenarios)

    /// Trigger the same refresh path that `ChatView.onAppear` uses.
    func loadActivities() async {
        await viewModel.loadActivities()
    }

    /// Trigger the same refresh path that a banner / pull-to-refresh
    /// tap uses.
    func manualRefresh() async {
        await viewModel.manualRefresh()
    }

    /// Poll `viewModel.syncState` at 10ms intervals until it matches
    /// the expected state, or `timeout` elapses. Throws on timeout.
    func awaitSyncState(_ expected: SessionSyncState, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if sameShape(viewModel.syncState, expected) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ScenarioError.syncStateTimeout(expected: expected, actual: viewModel.syncState)
    }

    /// Poll `session.activities.count` until it matches, or throw.
    func awaitActivityCount(_ expected: Int, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if session.activities.count == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ScenarioError.activityCountTimeout(expected: expected, actual: session.activities.count)
    }

    /// Enum-case equality that ignores associated values (`.stale("a")`
    /// should match `.stale("b")` for scenario purposes).
    private func sameShape(_ lhs: SessionSyncState, _ rhs: SessionSyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing): return true
        case (.stale, .stale), (.failed, .failed): return true
        default: return false
        }
    }
}

enum ScenarioError: Error, CustomStringConvertible {
    case syncStateTimeout(expected: SessionSyncState, actual: SessionSyncState)
    case activityCountTimeout(expected: Int, actual: Int)

    var description: String {
        switch self {
        case let .syncStateTimeout(expected, actual):
            return "sync state never became \(expected); stuck at \(actual)"
        case let .activityCountTimeout(expected, actual):
            return "activity count never reached \(expected); stuck at \(actual)"
        }
    }
}
