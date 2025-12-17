import SwiftUI
import SwiftData
import JoolsKit

/// View model for the dashboard
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var tasksUsed: Int = 0
    @Published var tasksLimit: Int = 15  // Default to free tier
    @Published var errorMessage: String?

    func refresh(using dependencies: AppDependency, modelContext: ModelContext) {
        Task {
            await refreshAsync(using: dependencies, modelContext: modelContext)
        }
    }

    func refreshAsync(using dependencies: AppDependency, modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Fetch and sync sources
            let sourcesResponse = try await dependencies.apiClient.listSources()
            syncSources(sourcesResponse.allItems, to: modelContext)

            // Fetch and sync sessions
            let sessionsResponse = try await dependencies.apiClient.listSessions()
            syncSessions(sessionsResponse.allItems, to: modelContext)

            // Save changes
            try modelContext.save()

        } catch {
            errorMessage = error.localizedDescription
            print("Dashboard refresh failed: \(error)")
        }
    }

    // MARK: - Private Sync Methods

    private func syncSources(_ dtos: [SourceDTO], to context: ModelContext) {
        for dto in dtos {
            // Check if source already exists
            let descriptor = FetchDescriptor<SourceEntity>(
                predicate: #Predicate { $0.id == dto.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                // Update existing
                existing.name = dto.name
                existing.owner = dto.githubRepo.owner
                existing.repo = dto.githubRepo.repo
                existing.lastSyncedAt = Date()
            } else {
                // Insert new
                let entity = SourceEntity(from: dto)
                context.insert(entity)
            }
        }
    }

    private func syncSessions(_ dtos: [SessionDTO], to context: ModelContext) {
        for dto in dtos {
            // Check if session already exists
            let descriptor = FetchDescriptor<SessionEntity>(
                predicate: #Predicate { $0.id == dto.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                // Update existing session
                existing.title = dto.title ?? "Untitled"
                existing.prompt = dto.prompt
                existing.stateRaw = dto.state ?? SessionState.unspecified.rawValue
                existing.updatedAt = dto.updateTime ?? Date()

                if let output = dto.outputs?.first?.pullRequest {
                    existing.prURL = output.url
                    existing.prTitle = output.title
                    existing.prDescription = output.description
                }
            } else {
                // Insert new session
                let entity = SessionEntity(from: dto)
                context.insert(entity)
            }
        }
    }
}
