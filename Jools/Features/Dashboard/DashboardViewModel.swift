import SwiftUI
import SwiftData
import JoolsKit

/// View model for the dashboard
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var tasksUsedToday: Int = 0
    @Published var errorMessage: String?

    /// Daily task limit (Jules Pro = 100, Free = 15)
    /// Note: The Jules API doesn't expose this, so we default to Pro tier
    let dailyTaskLimit: Int = 100

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

            // Fetch and sync sessions (use larger pageSize to capture all today's sessions)
            let sessionsResponse = try await dependencies.apiClient.listSessions(pageSize: 100)
            syncSessions(sessionsResponse.allItems, to: modelContext)

            // Count sessions created today
            tasksUsedToday = countSessionsCreatedToday(sessionsResponse.allItems)
            print("DEBUG: Total sessions fetched: \(sessionsResponse.allItems.count), Today's count: \(tasksUsedToday)")

            // Save changes
            try modelContext.save()

        } catch {
            errorMessage = error.localizedDescription
            print("Dashboard refresh failed: \(error)")
        }
    }

    private func countSessionsCreatedToday(_ sessions: [SessionDTO]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return sessions.filter { session in
            guard let createTime = session.createTime else { return false }
            return createTime >= today
        }.count
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
