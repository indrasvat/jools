import SwiftUI
import JoolsKit

// MARK: - ActivitySnapshotRow
//
// Stateless row view for a single `ActivitySnapshot`. Every sub-row
// takes its data by value and renders. NONE of the row views
// observe `ChatViewModel`, `SessionEntity`, `ActivityEntity`, or any
// SwiftData `@Query` — the parent `ChatMessagesList` owns all
// observation surfaces, and the row is a pure `Snapshot -> View`
// transform.
//
// Plan approve/revise callbacks are passed as closures so the plan
// row doesn't need a reference to the view model either.

struct ActivitySnapshotRow: View {
    let snapshot: ActivitySnapshot
    let canRespondToPlan: Bool
    let onApprovePlan: () -> Void
    let onRevisePlan: () -> Void

    var body: some View {
        switch snapshot.kind {
        case .userMessage(let text):
            UserMessageRow(
                text: text,
                sendStatus: snapshot.sendStatus,
                timestamp: snapshot.createdAt
            )
            .id(snapshot.id)

        case .agentMessage(let segments):
            AgentMessageRow(
                segments: segments,
                timestamp: snapshot.createdAt
            )
            .id(snapshot.id)

        case .planGenerated(let plan):
            PlanRow(
                plan: plan,
                canRespond: canRespondToPlan,
                onApprove: onApprovePlan,
                onRevise: onRevisePlan
            )
            .id(snapshot.id)

        case .progressUpdated(let progress):
            ProgressRow(progress: progress)
                .id(snapshot.id)

        case .planApproved:
            PlanApprovedRow()
                .id(snapshot.id)

        case .sessionCompleted(let completion):
            CompletionRow(completion: completion)
                .id(snapshot.id)

        case .sessionFailed(let message):
            FailedRow(message: message)
                .id(snapshot.id)

        case .unsupported:
            EmptyView()
        }
    }
}

// MARK: - User message

private struct UserMessageRow: View {
    let text: String
    let sendStatus: SendStatus
    let timestamp: Date

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.joolsBody)
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.vertical, JoolsSpacing.sm)
                    .background(Color.joolsBubbleUser)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                HStack(spacing: JoolsSpacing.xxs) {
                    Text(timestamp, style: .time)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                    SendStatusIconFromSnapshot(status: sendStatus)
                }
            }
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

private struct SendStatusIconFromSnapshot: View {
    let status: SendStatus

    var body: some View {
        switch status {
        case .pending:
            ProgressView()
                .scaleEffect(0.6)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(Color.joolsError)
        }
    }
}

// MARK: - Agent message
//
// The key row for perf: renders the flat markdown segments. Each
// `.text` segment is a single `Text(AttributedString)`; structural
// segments (code, table, thematic break) get their own compact
// SwiftUI view. For a typical agent response (5 paragraphs + 1
// table + 1 code block) this is 4 SwiftUI views total — down from
// ~50 in the previous MarkdownText implementation.

private struct AgentMessageRow: View {
    let segments: [MarkdownSegment]
    let timestamp: Date

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.md) {
            JulesAvatarView()

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                    ForEach(segments) { segment in
                        MarkdownSegmentView(segment: segment)
                    }
                }
                .padding(.horizontal, JoolsSpacing.md)
                .padding(.vertical, JoolsSpacing.sm)
                .background(Color.joolsBubbleAgent)
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                Text(timestamp, style: .time)
                    .font(.joolsCaption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, JoolsSpacing.sm)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - MarkdownSegmentView
//
// The atomic renderer for one flat segment. Text segments are a
// single `Text(attributed)` — no nested ForEach, no per-inline
// views. Code blocks keep their dedicated scrollable container
// because they need horizontal overflow + monospaced font. Tables
// use SwiftUI's `Grid` for a compact layout.

struct MarkdownSegmentView: View {
    let segment: MarkdownSegment

    var body: some View {
        switch segment {
        case let .text(_, attributed):
            Text(attributed)
                .font(.joolsBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case let .codeBlock(_, language, code):
            CodeBlockSegmentView(language: language, code: code)

        case let .table(_, head, rows):
            TableSegmentView(head: head, rows: rows)

        case .thematicBreak:
            Divider()
                .padding(.vertical, JoolsSpacing.xs)
        }
    }
}

// MARK: - Code block segment

private struct CodeBlockSegmentView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JoolsSpacing.sm)
                    .padding(.top, JoolsSpacing.xs)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(JoolsSpacing.sm)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.joolsSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
    }
}

// MARK: - Table segment

private struct TableSegmentView: View {
    let head: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(head.enumerated()), id: \.offset) { idx, cell in
                        Text(cell)
                            .font(.joolsBody.weight(.semibold))
                            .padding(.horizontal, JoolsSpacing.sm)
                            .padding(.vertical, JoolsSpacing.xs)
                            .frame(minWidth: 60, alignment: .leading)
                        if idx < head.count - 1 {
                            Divider()
                        }
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { cellIdx, cell in
                            Text(cell)
                                .font(.joolsBody)
                                .padding(.horizontal, JoolsSpacing.sm)
                                .padding(.vertical, JoolsSpacing.xs)
                                .frame(minWidth: 60, alignment: .leading)
                            if cellIdx < row.count - 1 {
                                Divider()
                            }
                        }
                    }
                    if rowIdx < rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(Color.joolsSurfaceElevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: JoolsRadius.sm)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
    }
}

// MARK: - Plan row

private struct PlanRow: View {
    let plan: PlanSnapshot
    let canRespond: Bool
    let onApprove: () -> Void
    let onRevise: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.joolsPlanBorder)
                Text("Proposed Plan")
                    .font(.joolsHeadline)
                Spacer()
            }
            .padding(JoolsSpacing.md)

            Divider()
                .padding(.horizontal, JoolsSpacing.md)

            VStack(alignment: .leading, spacing: 0) {
                if plan.steps.isEmpty {
                    Text("Plan details would appear here...")
                        .font(.joolsBody)
                        .foregroundStyle(.secondary)
                        .padding(JoolsSpacing.md)
                } else {
                    ForEach(plan.steps) { step in
                        SnapshotPlanStepRow(step: step, number: step.id + 1)
                        if step.id < plan.steps.count - 1 {
                            Divider()
                                .padding(.leading, JoolsSpacing.xl + JoolsSpacing.md)
                        }
                    }
                }
            }

            if canRespond {
                Divider()
                    .padding(.horizontal, JoolsSpacing.md)

                HStack(spacing: JoolsSpacing.md) {
                    Button(action: onRevise) {
                        Label("Revise", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("plan.revise")

                    Button(action: onApprove) {
                        Label("Approve", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.joolsAccent)
                    .accessibilityIdentifier("plan.approve")
                }
                .padding(JoolsSpacing.md)
            }
        }
        .background(Color.joolsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsPlanBorder, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }
}

private struct SnapshotPlanStepRow: View {
    let step: PlanStepSnapshot
    let number: Int

    @State private var isExpanded = false

    private var hasDescription: Bool {
        if let desc = step.description, !desc.isEmpty, desc != step.title {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasDescription else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: JoolsSpacing.sm) {
                    StepNumberBadgeFromSnapshot(number: number, status: step.status)
                    Text(step.title)
                        .font(.joolsBody)
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if hasDescription {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm)

            if isExpanded, let desc = step.description, !desc.isEmpty {
                RenderedMarkdown(text: desc, font: .joolsCaption)
                    .opacity(0.65)
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.leading, 28 + JoolsSpacing.sm) // align with title text
                    .padding(.bottom, JoolsSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityIdentifier("plan.step.\(number)")
    }
}

private struct StepNumberBadgeFromSnapshot: View {
    let number: Int
    let status: PlanStepSnapshot.StepStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 28, height: 28)

            switch status {
            case .completed:
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(foregroundColor)
            case .inProgress:
                ProgressView()
                    .scaleEffect(0.6)
            case .pending:
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(foregroundColor)
            }
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .pending: return Color.joolsSurface
        case .inProgress: return Color.joolsAccent.opacity(0.15)
        case .completed: return Color.joolsSuccess.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return Color.joolsAccent
        case .completed: return Color.joolsSuccess
        }
    }
}

// MARK: - Progress row

private struct ProgressRow: View {
    let progress: ProgressSnapshot

    /// Whether the description body is expanded (for progress cards
    /// that have a long description, like "Running code review...").
    @State private var isExpanded = false

    /// True when the title has a description that adds information
    /// beyond what messageSegments already show (e.g. a URL).
    private var hasTitle: Bool { progress.title != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            // 1. Bash commands
            ForEach(progress.bashCommands) { bash in
                CommandCardView(
                    command: bash.command,
                    output: bash.output,
                    success: bash.success,
                    isRunning: false
                )
            }

            // 2. File update card from changeSet artifacts
            if !progress.changedFiles.isEmpty {
                FileUpdateView(files: progress.changedFiles) { _ in }
            }

            // 3. Title + description card — takes priority when a
            //    title exists, because messageSegments would just
            //    redundantly render the same title text. The card
            //    also surfaces the description (e.g. a URL) that
            //    messageSegments would miss entirely.
            if let title = progress.title {
                ProgressTitleCard(
                    title: title,
                    description: progress.descriptionText,
                    isExpanded: $isExpanded
                )
            } else if let desc = progress.descriptionText,
                      progress.bashCommands.isEmpty && progress.messageSegments.isEmpty {
                ProgressTitleCard(
                    title: desc,
                    description: nil,
                    isExpanded: $isExpanded
                )
            }

            // 4. Message segments — only when there's no title
            //    (otherwise the title card above already covers it)
            if !hasTitle && !progress.messageSegments.isEmpty {
                HStack(alignment: .top, spacing: JoolsSpacing.md) {
                    JulesAvatarView(size: 28)

                    VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                        ForEach(progress.messageSegments) { segment in
                            MarkdownSegmentView(segment: segment)
                        }
                    }
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.vertical, JoolsSpacing.sm)
                    .background(Color.joolsBubbleAgent)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, JoolsSpacing.md)
                .accessibilityIdentifier("chat.working-card")
            }
        }
    }
}

/// Compact progress card that shows a title and an optional
/// expandable description. Matches the Jules web UI's collapsible
/// progress cards (e.g. "Running code review ...").
private struct ProgressTitleCard: View {
    let title: String
    let description: String?
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.md) {
            JulesAvatarView(size: 28)

            VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                if let description, !description.isEmpty {
                    // Title + expandable description
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(title)
                                .font(.joolsBody.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        RenderedMarkdown(text: description, font: .joolsCaption)
                            .opacity(0.65)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else {
                    // Title only
                    Text(title)
                        .font(.joolsBody)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm)
            .background(Color.joolsBubbleAgent)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

            Spacer(minLength: 40)
        }
        .padding(.horizontal, JoolsSpacing.md)
        .accessibilityIdentifier("chat.progress-title")
    }
}

// MARK: - Plan approved

private struct PlanApprovedRow: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.joolsSuccess)
            Text("Plan approved - Jules is implementing...")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - Completion row
//
// Layout adapted from the Jules web UI "Ready for review" card:
// ┌──────────────────────────────────────┐
// │  ✓ Session completed          +N -N  │
// │  ┌─────────────────────────────────┐ │
// │  │ commit message ...              │ │
// │  └─────────────────────────────────┘ │
// │  [file pills scrollable ...]         │
// │  ┌─────────────────────────────────┐ │
// │  │ ⑂ Pull Request           Open   │ │
// │  │ PR title                        │ │
// │  │ View PR ↗    Copy URL           │ │
// │  └─────────────────────────────────┘ │
// └──────────────────────────────────────┘

private struct CompletionRow: View {
    let completion: CompletionSnapshot

    @Environment(\.openURL) private var openURL
    @State private var showingDiffViewer = false
    @State private var showCopiedToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: status + diff stats
            HStack {
                HStack(spacing: JoolsSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.joolsSuccess)
                    Text("Session completed")
                        .font(.joolsBody.weight(.semibold))
                }

                Spacer()

                if completion.diffAdditions > 0 || completion.diffDeletions > 0 {
                    HStack(spacing: JoolsSpacing.sm) {
                        Text("+\(completion.diffAdditions)")
                            .foregroundStyle(Color.joolsSuccess)
                            .fontWeight(.semibold)
                        Text("-\(completion.diffDeletions)")
                            .foregroundStyle(Color.joolsError)
                            .fontWeight(.semibold)
                    }
                    .font(.joolsCaption)
                }
            }
            .padding(JoolsSpacing.md)

            // Commit message in a dark inset card
            if let message = completion.commitMessage, !message.isEmpty {
                Text(message)
                    .font(.joolsCaption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .padding(JoolsSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.joolsSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.bottom, JoolsSpacing.sm)
            }

            // Changed files as scrollable pills
            if !completion.changedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JoolsSpacing.xs) {
                        ForEach(completion.changedFiles, id: \.self) { file in
                            FilePill(filename: file, status: .modified) {
                                if !completion.diffFiles.isEmpty {
                                    showingDiffViewer = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, JoolsSpacing.md)
                }
                .padding(.bottom, JoolsSpacing.sm)
            }

            // Duration
            if completion.duration > 0 {
                HStack {
                    Spacer()
                    HStack(spacing: JoolsSpacing.xxs) {
                        Image(systemName: "clock")
                        Text("~\(Self.formatDuration(completion.duration))")
                    }
                    .font(.joolsCaption)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, JoolsSpacing.md)
                .padding(.bottom, JoolsSpacing.xs)
            }

            // PR card (only when session produced a pull request)
            if let prURL = completion.prURL {
                Divider()
                    .padding(.horizontal, JoolsSpacing.md)

                VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                    HStack(spacing: JoolsSpacing.xs) {
                        Image(systemName: "arrow.triangle.pull")
                            .foregroundStyle(Color.joolsAccent)
                        Text("Pull Request")
                            .font(.joolsCaption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        PRStatusBadge(status: .open)
                    }

                    if let title = completion.prTitle {
                        Text(title)
                            .font(.joolsBody)
                            .lineLimit(2)
                    }

                    HStack {
                        // Use Button + openURL instead of Link.
                        // Link inside a List row expands its tap
                        // target to fill the entire row — a known
                        // SwiftUI behavior. Button respects its
                        // own bounds.
                        Button {
                            if let url = URL(string: prURL) {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: JoolsSpacing.xxs) {
                                Image(systemName: "arrow.up.right.square")
                                Text("View PR")
                            }
                            .font(.joolsCaption.weight(.medium))
                            .foregroundStyle(Color.joolsAccent)
                            .padding(.horizontal, JoolsSpacing.sm)
                            .padding(.vertical, JoolsSpacing.xxs)
                            .background(Color.joolsAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = prURL
                            HapticManager.shared.lightImpact()
                            withAnimation { showCopiedToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showCopiedToast = false }
                            }
                        } label: {
                            HStack(spacing: JoolsSpacing.xxs) {
                                Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                                Text(showCopiedToast ? "Copied!" : "Copy URL")
                            }
                            .font(.joolsCaption)
                            .foregroundStyle(showCopiedToast ? Color.joolsSuccess : .secondary)
                            .padding(.horizontal, JoolsSpacing.sm)
                            .padding(.vertical, JoolsSpacing.xxs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(JoolsSpacing.md)
            }
        }
        .background(Color.joolsSuccess.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsSuccess.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
        .sheet(isPresented: $showingDiffViewer) {
            NavigationStack {
                DiffViewerView(
                    title: completion.commitMessage ?? "Changes",
                    files: completion.diffFiles
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingDiffViewer = false }
                    }
                }
            }
        }
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 1 { return "<1 min" }
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }
}

// MARK: - Rendered markdown helper
//
// Reusable view for rendering markdown text in collapsible sections
// (progress descriptions, plan step details). Uses the same
// FlatMarkdownRenderer pipeline as agent message bubbles.

private struct RenderedMarkdown: View {
    let segments: [MarkdownSegment]

    init(text: String, font: Font = .joolsCaption) {
        // Render once at init; the segments are Equatable so SwiftUI
        // will skip re-rendering if the text hasn't changed.
        self.segments = FlatMarkdownRenderer.render(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
            ForEach(segments) { segment in
                MarkdownSegmentView(segment: segment)
            }
        }
    }
}

// MARK: - Failed row

private struct FailedRow: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.joolsError)
            Text(message)
                .font(.joolsBody)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.joolsError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }
}
