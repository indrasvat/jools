import SwiftUI
import JoolsKit

// MARK: - Diff Statistics

struct DiffStats: Equatable {
    let additions: Int
    let deletions: Int
    let filesChanged: Int

    static let empty = DiffStats(additions: 0, deletions: 0, filesChanged: 0)
}

// MARK: - Completion Card

/// Card displayed when a session completes successfully
struct CompletionCardView: View {
    let session: SessionEntity
    let activity: ActivityEntity
    let diffStats: DiffStats
    let changedFiles: [String]
    let duration: TimeInterval

    @State private var showShareSheet = false
    @State private var showCopiedToast = false

    private var commitMessage: String {
        activity.messageContent ?? session.title
    }

    /// Parsed unified-diff for the per-file viewer. Pulled directly
    /// from the activity's gitPatch so we don't pay the parse cost
    /// unless something actually opens the diff.
    private var diffFiles: [DiffFile] {
        activity.gitPatch?.parsedFiles ?? []
    }

    private var hasDiff: Bool { !diffFiles.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with success indicator and diff stats
            header

            Divider()

            // Commit message / summary
            commitSection

            if hasDiff {
                Divider()
                viewDiffLink
            }

            Divider()

            // PR card if available
            if let prURL = session.prURL {
                prCard(url: prURL)
                Divider()
            }

            // Footer with feedback and actions
            footer
        }
        .background(Color.joolsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsSuccess, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }

    private var viewDiffLink: some View {
        NavigationLink {
            DiffViewerView(title: session.title, files: diffFiles)
        } label: {
            HStack(spacing: JoolsSpacing.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(Color.joolsAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("View diff")
                        .font(.joolsBody.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(diffFiles.count) \(diffFiles.count == 1 ? "file" : "files") — +\(diffStats.additions) / −\(diffStats.deletions)")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(JoolsSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("completion.viewDiff")
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            // Success icon and text
            HStack(spacing: JoolsSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.joolsSuccess)
                    .font(.title3)

                Text("Session Complete!")
                    .font(.joolsHeadline)
            }

            Spacer()

            // Diff stats
            DiffStatsView(additions: diffStats.additions, deletions: diffStats.deletions)
        }
        .padding(JoolsSpacing.md)
    }

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            Text(commitMessage)
                .font(.joolsBody)
                .foregroundStyle(.primary)
                .lineLimit(6)

            // File pills for changed files. The status is hardcoded
            // to `.modified` because Jules's `GitPatchDTO.changedFiles`
            // only extracts paths from the unified-diff headers — the
            // per-file change type (added / deleted / renamed) isn't
            // propagated out of `DiffParser` today. When we enrich
            // `changedFiles` with per-file status (e.g. by reading
            // `/dev/null` markers from the `diff --git` preambles),
            // switch this to `file.changeStatus`. (CodeRabbit review.)
            if !changedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JoolsSpacing.xs) {
                        ForEach(changedFiles, id: \.self) { file in
                            FilePill(filename: file, status: .modified) {
                                // No action needed for now
                            }
                        }
                    }
                }
            }
        }
        .padding(JoolsSpacing.md)
    }

    private func prCard(url: String) -> some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack(spacing: JoolsSpacing.xs) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(Color.joolsAccent)

                Text("Pull Request")
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)

                Spacer()

                // TODO: Jules's Session.outputs.pullRequest DTO doesn't
                // carry a merged/closed state yet — only the URL, title
                // and description. Until the API surfaces live PR
                // state, we show "Open" as a placeholder. Once the API
                // catches up, switch this to `session.prState` and drop
                // the hardcoded `.open`. (CodeRabbit review.)
                PRStatusBadge(status: .open)
            }

            Text(session.prTitle ?? session.title)
                .font(.joolsBody)
                .lineLimit(2)

            if let description = session.prDescription {
                Text(description)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Action buttons
            HStack(spacing: JoolsSpacing.md) {
                // Open in browser button
                if let prURL = URL(string: url) {
                    Link(destination: prURL) {
                        HStack(spacing: JoolsSpacing.xxs) {
                            Image(systemName: "arrow.up.right.square")
                            Text("View PR")
                        }
                        .font(.joolsCaption)
                        .foregroundStyle(Color.joolsAccent)
                    }
                }

                // Copy URL button
                Button {
                    UIPasteboard.general.string = url
                    HapticManager.shared.lightImpact()
                    withAnimation {
                        showCopiedToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopiedToast = false
                        }
                    }
                } label: {
                    HStack(spacing: JoolsSpacing.xxs) {
                        Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                        Text(showCopiedToast ? "Copied!" : "Copy URL")
                    }
                    .font(.joolsCaption)
                    .foregroundStyle(showCopiedToast ? Color.joolsSuccess : .secondary)
                }
            }
        }
        .padding(JoolsSpacing.md)
        .background(Color.joolsBackground)
    }

    private var footer: some View {
        HStack {
            // Feedback buttons
            FeedbackButtons(sessionId: session.id)

            Spacer()

            // Duration
            HStack(spacing: JoolsSpacing.xxs) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(formatDuration(duration))
                    .font(.joolsCaption)
            }
            .foregroundStyle(.secondary)

            // Share button — only meaningful when there's a PR URL to
            // share. Without this guard, repoless completions would
            // open an empty share sheet (the inner content was already
            // gated on prURL but the button itself was always visible,
            // landing the user in a dead-end modal). CodeRabbit review.
            if session.prURL != nil {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(Color.joolsAccent)
                }
                .accessibilityLabel("Share PR")
            }
        }
        .padding(JoolsSpacing.md)
        .sheet(isPresented: $showShareSheet) {
            if let prURL = session.prURL, let url = URL(string: prURL) {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMins = minutes % 60
        return "\(hours)h \(remainingMins)m"
    }
}

// MARK: - Diff Stats View

struct DiffStatsView: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            Text("+\(additions)")
                .foregroundStyle(Color.joolsSuccess)
                .fontWeight(.semibold)

            Text("-\(deletions)")
                .foregroundStyle(Color.joolsError)
                .fontWeight(.semibold)
        }
        .font(.joolsCaption)
    }
}

// MARK: - PR Status Badge

enum PRStatus {
    case open
    case merged
    case closed

    var text: String {
        switch self {
        case .open: return "Open"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .open: return .green
        case .merged: return .purple
        case .closed: return .red
        }
    }
}

struct PRStatusBadge: View {
    let status: PRStatus

    var body: some View {
        Text(status.text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(status.color)
            .padding(.horizontal, JoolsSpacing.xs)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Feedback Buttons

struct FeedbackButtons: View {
    let sessionId: String
    @State private var feedback: Feedback? = nil

    enum Feedback { case positive, negative }

    var body: some View {
        HStack(spacing: JoolsSpacing.sm) {
            Button {
                HapticManager.shared.lightImpact()
                withAnimation {
                    feedback = .positive
                }
                // TODO: Send feedback to API
            } label: {
                Image(systemName: feedback == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.body)
                    .foregroundStyle(feedback == .positive ? Color.joolsSuccess : .secondary)
            }

            Button {
                HapticManager.shared.lightImpact()
                withAnimation {
                    feedback = .negative
                }
                // TODO: Send feedback to API
            } label: {
                Image(systemName: feedback == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.body)
                    .foregroundStyle(feedback == .negative ? Color.joolsError : .secondary)
            }

            Text("Feedback")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview("Completion Card") {
    CompletionCardView(
        session: SessionEntity(
            id: "preview",
            title: "feat: add user authentication",
            prompt: "Add user authentication",
            state: .completed,
            sourceId: "github/owner/repo",
            sourceBranch: "main",
            automationMode: .autoCreatePR,
            requirePlanApproval: true,
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date()
        ),
        activity: ActivityEntity(
            id: "preview",
            type: .sessionCompleted,
            createdAt: Date(),
            contentJSON: Data()
        ),
        diffStats: DiffStats(additions: 1492, deletions: 47, filesChanged: 12),
        changedFiles: ["src/auth/login.ts", "src/auth/session.ts", "src/components/LoginForm.tsx"],
        duration: 1320 // 22 minutes
    )
    .padding()
    .background(Color.joolsBackground)
}
