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

    var body: some View {
        HStack(alignment: .center, spacing: JoolsSpacing.sm) {
            StepNumberBadgeFromSnapshot(number: number, status: step.status)
            Text(step.title)
                .font(.joolsBody)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, JoolsSpacing.md)
        .padding(.vertical, JoolsSpacing.sm)
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

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            ForEach(progress.bashCommands) { bash in
                CommandCardView(
                    command: bash.command,
                    output: bash.output,
                    success: bash.success,
                    isRunning: false
                )
            }

            if !progress.messageSegments.isEmpty {
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

private struct CompletionRow: View {
    let completion: CompletionSnapshot

    @State private var showingDiffViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack(spacing: JoolsSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.joolsSuccess)
                Text("Session completed")
                    .font(.joolsBody.weight(.semibold))
                Spacer()
            }

            if let message = completion.commitMessage, !message.isEmpty {
                Text(message)
                    .font(.joolsBody)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
            }

            if completion.diffAdditions > 0 || completion.diffDeletions > 0 {
                HStack(spacing: JoolsSpacing.sm) {
                    Label("+\(completion.diffAdditions)", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.joolsSuccess)
                    Label("-\(completion.diffDeletions)", systemImage: "minus.circle.fill")
                        .foregroundStyle(Color.joolsError)
                }
                .font(.joolsCaption)
            }

            if !completion.changedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JoolsSpacing.xs) {
                        ForEach(completion.changedFiles, id: \.self) { file in
                            // Tapping any file pill opens the full
                            // DiffViewerView as a sheet so users
                            // can read the actual hunk-level changes,
                            // not just the file name. This wiring was
                            // lost when the chat surface migrated to
                            // the snapshot architecture; restoring
                            // it here uses `completion.diffFiles`
                            // which is pre-parsed by
                            // ActivitySnapshotBuilder.
                            FilePill(filename: file, status: .modified) {
                                if !completion.diffFiles.isEmpty {
                                    showingDiffViewer = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(JoolsSpacing.md)
        .background(Color.joolsSuccess.opacity(0.08))
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
