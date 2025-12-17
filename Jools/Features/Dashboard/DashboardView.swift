import SwiftUI
import SwiftData

/// Main dashboard view showing sources and recent sessions
struct DashboardView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SessionEntity.updatedAt, order: .reverse) private var sessions: [SessionEntity]
    @Query private var sources: [SourceEntity]

    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: JoolsSpacing.lg) {
                    // Usage Stats Card
                    UsageStatsCard(
                        tasksUsed: viewModel.tasksUsed,
                        tasksLimit: viewModel.tasksLimit
                    )

                    // Sources Section
                    if !sources.isEmpty {
                        SourcesSection(sources: sources)
                    }

                    // Recent Sessions Section
                    if !sessions.isEmpty {
                        RecentSessionsSection(sessions: Array(sessions.prefix(5)))
                    }

                    // Empty State
                    if sessions.isEmpty && sources.isEmpty {
                        EmptyDashboardView()
                    }
                }
                .padding()
            }
            .navigationTitle("Jools")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.refresh(using: dependencies) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await viewModel.refreshAsync(using: dependencies)
            }
        }
        .task {
            await viewModel.refreshAsync(using: dependencies)
        }
    }
}

// MARK: - Supporting Views

struct UsageStatsCard: View {
    let tasksUsed: Int
    let tasksLimit: Int

    private var progress: Double {
        guard tasksLimit > 0 else { return 0 }
        return Double(tasksUsed) / Double(tasksLimit)
    }

    private var isNearLimit: Bool {
        progress > 0.8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                Text("Today's Usage")
                    .font(.joolsHeadline)
                Spacer()
                Text("\(tasksUsed)/\(tasksLimit)")
                    .font(.joolsBody)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(isNearLimit ? .joolsWarning : .joolsAccent)

            if isNearLimit {
                Text("You're approaching your daily limit")
                    .font(.joolsCaption)
                    .foregroundStyle(.joolsWarning)
            }
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

struct SourcesSection: View {
    let sources: [SourceEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            Text("Sources")
                .font(.joolsHeadline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JoolsSpacing.sm) {
                    ForEach(sources, id: \.id) { source in
                        SourceCard(source: source)
                    }
                }
            }
        }
    }
}

struct SourceCard: View {
    let source: SourceEntity

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.joolsAccent)

            Text(source.repo)
                .font(.joolsHeadline)
                .lineLimit(1)

            Text(source.owner)
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 140)
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

struct RecentSessionsSection: View {
    let sessions: [SessionEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                Text("Recent Sessions")
                    .font(.joolsHeadline)
                Spacer()
                NavigationLink("See All") {
                    SessionsListView()
                }
                .font(.joolsCaption)
            }

            ForEach(sessions, id: \.id) { session in
                SessionRow(session: session)
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionEntity

    var body: some View {
        NavigationLink {
            ChatView(session: session)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                    Text(session.title)
                        .font(.joolsBody)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(session.prompt)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                SessionStateBadge(state: session.state)
            }
            .padding()
            .background(Color.joolsSurface)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyDashboardView: View {
    var body: some View {
        VStack(spacing: JoolsSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Sessions Yet")
                .font(.joolsTitle3)

            Text("Connect a repository and create your first session")
                .font(.joolsBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, JoolsSpacing.xxl)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppDependency())
}
