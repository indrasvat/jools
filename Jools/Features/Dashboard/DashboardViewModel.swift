import SwiftUI
import SwiftData
import JoolsKit

/// View model for the dashboard
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var tasksUsedToday: Int = 0
    @Published var errorMessage: String?

    func refresh(using dependencies: AppDependency, modelContext: ModelContext) {
        Task {
            await refreshAsync(using: dependencies, modelContext: modelContext)
        }
    }

    func refreshAsync(using dependencies: AppDependency, modelContext: ModelContext) async {
        guard !dependencies.isUITestMode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Walk every page of sources and sessions so users with
            // more than `pageSize` of either don't silently lose
            // visibility of older entries on refresh.
            let allSources = try await dependencies.apiClient.listAllSources()
            try Task.checkCancellation()
            syncSources(allSources, to: modelContext)

            let allSessions = try await dependencies.apiClient.listAllSessions(pageSize: 100)
            try Task.checkCancellation()
            syncSessions(allSessions, to: modelContext)

            // Count sessions created today
            tasksUsedToday = countSessionsCreatedToday(allSessions)

            // Save changes
            try modelContext.save()

            // Check for state transitions that should trigger notifications.
            // Inline await (not detached) preserves cancellation propagation.
            await dependencies.notificationManager?.checkForTransitions(allSessions)

        } catch is CancellationError {
            // Pull-to-refresh interrupted by another pull, navigation
            // away, or scene phase change. Not a failure — leave the
            // last successful snapshot on screen and stay quiet.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession's own cancellation path — same story as above.
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func countSessionsCreatedToday(_ sessions: [SessionDTO]) -> Int {
        // Use UTC calendar since API returns UTC timestamps
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let todayUTC = utcCalendar.startOfDay(for: Date())

        let todaySessions = sessions.filter { session in
            guard let createTime = session.createTime else { return false }
            return createTime >= todayUTC
        }
        return todaySessions.count
    }

    // MARK: - Private Sync Methods

    private func syncSources(_ dtos: [SourceDTO], to context: ModelContext) {
        for dto in dtos {
            // Check if source already exists
            let descriptor = FetchDescriptor<SourceEntity>(
                predicate: #Predicate { $0.id == dto.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                // Refresh fields from server. `name` heals in place for
                // any row persisted by an older app version that stored
                // `name == id`.
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

                if let pr = dto.outputs?.lazy.compactMap({ $0.pullRequest }).first {
                    existing.prURL = pr.url
                    existing.prTitle = pr.title
                    existing.prDescription = pr.description
                }
            } else {
                // Insert new session
                let entity = SessionEntity(from: dto)
                context.insert(entity)
            }
        }
    }
}
