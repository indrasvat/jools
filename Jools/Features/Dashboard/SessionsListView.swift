import SwiftUI
import SwiftData

/// List view showing all sessions
struct SessionsListView: View {
    @Query(sort: \SessionEntity.updatedAt, order: .reverse) private var sessions: [SessionEntity]
    @State private var searchText: String = ""

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
        List {
            ForEach(filteredSessions, id: \.id) { session in
                NavigationLink {
                    ChatView(session: session)
                } label: {
                    SessionListRow(session: session)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Sessions")
        .searchable(text: $searchText, prompt: "Search sessions")
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a new session to get started")
                )
            } else if filteredSessions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct SessionListRow: View {
    let session: SessionEntity

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
            HStack {
                Text(session.title)
                    .font(.joolsHeadline)
                    .lineLimit(1)

                Spacer()

                SessionStateBadge(state: session.state)
            }

            Text(session.prompt)
                .font(.joolsBody)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Image(systemName: "folder")
                    .font(.caption2)
                Text(session.sourceId.replacingOccurrences(of: "sources/", with: ""))
                    .font(.joolsCaption)

                Spacer()

                Text(session.updatedAt, style: .relative)
                    .font(.joolsCaption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, JoolsSpacing.xs)
    }
}

#Preview {
    NavigationStack {
        SessionsListView()
    }
}
