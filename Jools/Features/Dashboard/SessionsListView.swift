import SwiftUI
import SwiftData
import JoolsKit

/// List view showing all sessions
struct SessionsListView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SessionEntity.updatedAt, order: .reverse) private var sessions: [SessionEntity]
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var pendingDeletion: SessionEntity?
    @State private var deletionError: String?
    @State private var showDeletionError = false
    /// Throttle for the on-appear refresh — we want to feel fresh when
    /// the user comes back to the list, but not hammer the API every
    /// time the tab gains focus.
    @State private var lastRefreshAt: Date?
    private let onAppearRefreshInterval: TimeInterval = 15

    private var filteredSessions: [SessionEntity] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.prompt.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSessions, id: \.id) { session in
                    NavigationLink {
                        ChatView(session: session)
                    } label: {
                        SessionListRow(session: session)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("session.row.\(session.id)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletion = session
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("session.row.delete.\(session.id)")
                    }
                }

                if !sessions.isEmpty || !searchText.isEmpty {
                    Section {
                        MadeWithJoolsFooter(style: .list)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Sessions")
            .searchable(text: $searchText, prompt: "Search sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { Task { await refreshSessions(reason: .manual) } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("sessions.refresh")
                }
            }
            .refreshable {
                await refreshSessions(reason: .manual)
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Pull to refresh or create a session on jules.google.com")
                    )
                } else if filteredSessions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .alert(
                "Delete this session?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { session in
                Button("Delete", role: .destructive) {
                    Task { await delete(session: session) }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { session in
                Text("\"\(session.title)\" will be removed from Jules. This can't be undone.")
            }
            .alert("Couldn't delete session", isPresented: $showDeletionError, presenting: deletionError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        .task {
            guard !dependencies.isUITestMode else { return }
            await refreshSessions(reason: .firstAppearance)
        }
        .onAppear {
            guard !dependencies.isUITestMode else { return }
            // Re-enter the tab? If it's been a while since the last
            // refresh, kick off a fresh listSessions in the background
            // so cached row states (the "Starting" -> "Needs Approval"
            // staleness) reconcile before the user notices.
            if shouldRefreshOnAppear {
                Task { await refreshSessions(reason: .reappearance) }
            }
        }
    }

    private enum RefreshReason {
        case firstAppearance
        case reappearance
        case manual
    }

    private var shouldRefreshOnAppear: Bool {
        guard let lastRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) > onAppearRefreshInterval
    }

    private func refreshSessions(reason: RefreshReason = .manual) async {
        guard !dependencies.isUITestMode else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Walk every page so users with more than the default
            // page size don't see older sessions vanish from the list
            // (and from search) after each refresh.
            let allSessions = try await dependencies.apiClient.listAllSessions(pageSize: 100)
            syncSessions(allSessions)
            try modelContext.save()
            lastRefreshAt = Date()

            // Check for state transitions that should trigger notifications.
            await dependencies.notificationManager?.checkForTransitions(allSessions)
        } catch is CancellationError {
            // Pull-to-refresh interrupted by another pull or scene
            // change. Not a failure — silently keep the cached data.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            print("Failed to refresh sessions (\(reason)): \(error)")
        }
    }

    private func delete(session: SessionEntity) async {
        let id = session.id
        let title = session.title
        pendingDeletion = nil

        HapticManager.shared.warning()

        do {
            try await dependencies.apiClient.deleteSession(id: id)
            modelContext.delete(session)
            try modelContext.save()
            HapticManager.shared.success()
        } catch let NetworkError.notFound {
            // Already gone server-side; drop the local copy too.
            modelContext.delete(session)
            try? modelContext.save()
        } catch {
            // Surface the failure but leave the row in place so the
            // user can retry without losing the entry.
            deletionError = "Couldn't delete \"\(title)\": \(error.localizedDescription)"
            showDeletionError = true
            HapticManager.shared.error()
        }
    }

    private func syncSessions(_ dtos: [SessionDTO]) {
        for dto in dtos {
            let descriptor = FetchDescriptor<SessionEntity>(
                predicate: #Predicate { $0.id == dto.id }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
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
                let entity = SessionEntity(from: dto)
                modelContext.insert(entity)
            }
        }
    }
}

struct SessionListRow: View {
    let session: SessionEntity

    var body: some View {
        let resolved = session.resolvedState

        VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
            HStack {
                Text(session.title)
                    .font(.joolsHeadline)
                    .lineLimit(1)

                Spacer()

                SessionStateBadge(resolved: resolved)
            }

            Text(session.prompt)
                .font(.joolsBody)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: JoolsSpacing.xs) {
                if session.isRepoless {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("No repo")
                        .font(.joolsCaption)
                } else {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(displaySourceLabel(for: session))
                        .font(.joolsCaption)
                        .lineLimit(1)
                }

                Spacer()

                Text(session.updatedAt, style: .relative)
                    .font(.joolsCaption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, JoolsSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.row.content.\(session.id)")
    }

    private func displaySourceLabel(for session: SessionEntity) -> String {
        // Source IDs come back from the API in two known shapes:
        //   "sources/<opaque>" — full resource name
        //   "<opaque>"          — bare id (usually `github/owner/repo`)
        // Strip the "sources/" prefix for display, then prefer the
        // owner/repo tail if it parses cleanly.
        let stripped = session.sourceId.hasPrefix("sources/")
            ? String(session.sourceId.dropFirst("sources/".count))
            : session.sourceId
        return stripped
    }
}

#Preview {
    NavigationStack {
        SessionsListView()
    }
}
