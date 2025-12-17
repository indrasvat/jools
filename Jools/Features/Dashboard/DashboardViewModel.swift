import SwiftUI
import JoolsKit

/// View model for the dashboard
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var tasksUsed: Int = 0
    @Published var tasksLimit: Int = 15  // Default to free tier

    func refresh(using dependencies: AppDependency) {
        Task {
            await refreshAsync(using: dependencies)
        }
    }

    func refreshAsync(using dependencies: AppDependency) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch sources
            let sourcesResponse = try await dependencies.apiClient.listSources()
            // TODO: Update SwiftData with sources

            // Fetch sessions
            let sessionsResponse = try await dependencies.apiClient.listSessions()
            // TODO: Update SwiftData with sessions

            // TODO: Fetch usage stats when API supports it

        } catch {
            // Handle error silently for now
            print("Dashboard refresh failed: \(error)")
        }
    }
}
