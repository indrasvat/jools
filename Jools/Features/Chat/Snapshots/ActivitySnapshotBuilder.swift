import Foundation
import JoolsKit

// MARK: - ActivitySnapshotBuilder
//
// Converts a `[ActivityEntity]` (SwiftData reference type) into a
// `[ActivitySnapshot]` (pure value type). This is the ONE place in
// the chat surface that touches SwiftData `@PersistedProperty`
// accessors — everything downstream is Sendable value types.
//
// Runs `@MainActor`-isolated because `ActivityEntity` is a SwiftData
// `@Model` and SwiftData types are main-actor by default. The output
// is `Sendable` so it can be passed across actor boundaries later
// (e.g. if we decide to move snapshot construction to a background
// actor for very long sessions).

enum ActivitySnapshotBuilder {

    /// Build snapshots for the chat list. Takes the `@Query` result
    /// as the primary source and falls back to the SwiftData
    /// relationship array if the `@Query` hasn't yet observed
    /// freshly inserted rows (brief race during initial load).
    @MainActor
    static func build(
        from query: [ActivityEntity],
        fallback: [ActivityEntity]
    ) -> [ActivitySnapshot] {
        let source: [ActivityEntity]
        if !query.isEmpty {
            source = query
        } else {
            source = fallback.sorted { $0.createdAt < $1.createdAt }
        }
        return source.compactMap { ActivitySnapshot(entity: $0) }
    }
}

// MARK: - ActivitySnapshot init from entity

extension ActivitySnapshot {

    @MainActor
    init?(entity: ActivityEntity) {
        guard let kind = Kind(entity: entity) else { return nil }
        self.id = entity.id
        self.type = entity.type
        self.createdAt = entity.createdAt
        self.isOptimistic = entity.isOptimistic
        self.sendStatus = entity.sendStatus
        self.kind = kind
    }
}

extension ActivitySnapshot.Kind {

    @MainActor
    init?(entity: ActivityEntity) {
        switch entity.type {
        case .userMessaged:
            self = .userMessage(text: entity.messageContent ?? "")

        case .agentMessaged:
            let segments = FlatMarkdownRenderer.render(entity.messageContent ?? "")
            self = .agentMessage(segments: segments)

        case .planGenerated:
            guard let plan = entity.plan, let rawSteps = plan.steps else {
                self = .planGenerated(snapshot: PlanSnapshot(steps: []))
                return
            }
            let steps = rawSteps.enumerated().map { index, step in
                PlanStepSnapshot(
                    id: index,
                    title: step.title ?? step.description ?? "Step \(index + 1)",
                    description: step.description,
                    status: PlanStepSnapshot.StepStatus(rawDTO: step.status)
                )
            }
            self = .planGenerated(snapshot: PlanSnapshot(steps: steps))

        case .progressUpdated:
            let segments = FlatMarkdownRenderer.render(entity.messageContent ?? "")
            let bash = entity.bashCommands.enumerated().compactMap { index, dto -> BashCommandSnapshot? in
                guard let command = dto.command else { return nil }
                return BashCommandSnapshot(
                    id: "\(entity.id)-cmd-\(index)",
                    command: command,
                    output: dto.output,
                    success: !dto.isLikelyFailure
                )
            }
            self = .progressUpdated(snapshot: ProgressSnapshot(
                title: entity.progressTitle,
                descriptionText: entity.progressDescription,
                bashCommands: bash,
                messageSegments: segments
            ))

        case .planApproved:
            self = .planApproved

        case .sessionCompleted:
            // Parse the unified-diff patch once here so the view
            // layer (CompletionRow / DiffViewerView) doesn't need
            // to touch the SwiftData entity at presentation time.
            // UnifiedDiffParser is pure-function and fast enough
            // to run on the main actor during snapshot construction.
            let parsedDiffFiles: [DiffFile]
            if let patch = entity.gitPatch?.unidiffPatch, !patch.isEmpty {
                parsedDiffFiles = UnifiedDiffParser.parse(patch)
            } else {
                parsedDiffFiles = []
            }
            self = .sessionCompleted(snapshot: CompletionSnapshot(
                commitMessage: entity.messageContent,
                diffAdditions: entity.diffAdditions,
                diffDeletions: entity.diffDeletions,
                changedFiles: entity.changedFiles,
                diffFiles: parsedDiffFiles,
                duration: 0
            ))

        case .sessionFailed:
            self = .sessionFailed(message: entity.messageContent ?? "Session failed")

        case .unknown:
            self = .unsupported(rawType: "UNKNOWN")
        }
    }
}
