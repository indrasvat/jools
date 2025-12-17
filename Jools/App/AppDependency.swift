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

    // MARK: - State

    @Published var isAuthenticated: Bool = false

    // MARK: - Initialization

    init() {
        // Initialize keychain manager
        self.keychainManager = KeychainManager()

        // Initialize API client
        self.apiClient = APIClient(keychain: keychainManager)

        // Initialize polling service
        self.pollingService = PollingService(api: apiClient)

        // Initialize SwiftData container
        do {
            let schema = Schema([
                SessionEntity.self,
                SourceEntity.self,
                ActivityEntity.self,
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Check if user is authenticated
        self.isAuthenticated = keychainManager.hasAPIKey()
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
    }
}
