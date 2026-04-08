import Foundation
import JoolsKit

// MARK: - ActivitySnapshot
//
// Value-type projection of `ActivityEntity` for the SwiftUI list.
// The chat list iterates these snapshots, NEVER the SwiftData
// entities, so ForEach identity resolution and cell layout never
// touch the SwiftData observation registrar — which was the leaf
// cost in the freeze samples after the polling-chain and
// @Observable-migration fixes took effect. (See
// `docs/Option_B_Implementation_Plan.md`.)
//
// All kinds are `Equatable + Sendable`, which (a) lets SwiftUI's
// List diff short-circuit unchanged rows, and (b) lets snapshot
// construction move off the main thread later without Sendable
// complaints. For the 3-hour spike we build snapshots on-main
// in the view body; the type is ready to move.

/// Immutable, value-type projection of a single activity for the
/// chat list.
struct ActivitySnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let type: ActivityType
    let createdAt: Date
    let isOptimistic: Bool
    let sendStatus: SendStatus
    let kind: Kind

    /// Render-path union. Each case carries exactly the data that
    /// the corresponding row view needs and nothing more. No
    /// back-references to the original SwiftData entity, no
    /// observer protocol conformances.
    enum Kind: Equatable, Sendable {
        case userMessage(text: String)
        case agentMessage(segments: [MarkdownSegment])
        case planGenerated(snapshot: PlanSnapshot)
        case progressUpdated(snapshot: ProgressSnapshot)
        case planApproved
        case sessionCompleted(snapshot: CompletionSnapshot)
        case sessionFailed(message: String)
        /// Fallback for unknown / unhandled activity types so we can
        /// debug the surface without dropping content silently.
        case unsupported(rawType: String)
    }
}

// MARK: - Nested snapshot types

struct PlanSnapshot: Equatable, Sendable {
    let steps: [PlanStepSnapshot]
}

struct PlanStepSnapshot: Equatable, Sendable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let status: StepStatus

    /// Local enum instead of the string-backed DTO field so the
    /// snapshot is fully self-contained and trivially Equatable.
    enum StepStatus: String, Equatable, Sendable {
        case pending
        case inProgress
        case completed

        init(rawDTO: String?) {
            switch (rawDTO ?? "").lowercased() {
            case "completed", "done":
                self = .completed
            case "in_progress", "running":
                self = .inProgress
            default:
                self = .pending
            }
        }
    }
}

struct ProgressSnapshot: Equatable, Sendable {
    let title: String?
    let descriptionText: String?
    let bashCommands: [BashCommandSnapshot]
    let messageSegments: [MarkdownSegment]
}

struct BashCommandSnapshot: Equatable, Sendable, Identifiable {
    /// Stable string id — derived from command + output hash so
    /// that equal bash outputs share an id and the snapshot diff
    /// treats them as the same row.
    let id: String
    let command: String
    let output: String?
    let success: Bool
}

struct CompletionSnapshot: Equatable, Sendable {
    let commitMessage: String?
    let diffAdditions: Int
    let diffDeletions: Int
    let changedFiles: [String]
    /// Parsed per-file diff hunks for the `DiffViewerView`. Parsed
    /// eagerly in `ActivitySnapshotBuilder` so the view layer doesn't
    /// have to touch the SwiftData entity at presentation time.
    /// Empty when the session produced no unified-diff patch.
    let diffFiles: [DiffFile]
    let duration: TimeInterval
}

// MARK: - MarkdownSegment
//
// The flattened markdown-render output. Each markdown document
// produces a sequence of these, where the overwhelming majority
// are `.text` (containing a multi-block attributed string built
// from paragraphs, headings, lists, blockquotes, inline runs) and
// only fenced code blocks + tables + thematic breaks get dedicated
// segments because they need structural layout.
//
// This is the SwiftUI equivalent of Jules's web rendering, which
// produces ~3 flat HTML elements per markdown block. Our old
// `MarkdownText` view produced a ~50-deep SwiftUI view tree for
// the same content.

enum MarkdownSegment: Equatable, Sendable, Identifiable {
    /// A multi-block attributed run. Packs paragraphs, headings,
    /// lists, blockquotes, inline bold/italic/code/link, and
    /// soft/hard breaks into a single `AttributedString`. The row
    /// view renders this as a single `Text(attributed)`.
    case text(id: String, attributed: AttributedString)

    /// Fenced code block. Rendered with a monospaced container.
    case codeBlock(id: String, language: String?, code: String)

    /// GitHub-flavored markdown table. Rendered with a compact
    /// grid view (SwiftUI `Grid` under the hood).
    case table(id: String, head: [AttributedString], rows: [[AttributedString]])

    /// Thematic break (`---`). Renders as a horizontal divider.
    case thematicBreak(id: String)

    var id: String {
        switch self {
        case .text(let id, _),
             .codeBlock(let id, _, _),
             .table(let id, _, _),
             .thematicBreak(let id):
            return id
        }
    }
}
