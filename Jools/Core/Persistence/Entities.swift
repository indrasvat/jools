import Foundation
import SwiftData
import JoolsKit

// MARK: - Source Entity

@Model
final class SourceEntity {
    @Attribute(.unique) var id: String
    var name: String
    var owner: String
    var repo: String
    var lastSyncedAt: Date?

    init(id: String, name: String, owner: String, repo: String) {
        self.id = id
        self.name = name
        self.owner = owner
        self.repo = repo
        self.lastSyncedAt = Date()
    }

    convenience init(from dto: SourceDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            owner: dto.githubRepo.owner,
            repo: dto.githubRepo.repo
        )
    }

    var displayName: String {
        "\(owner)/\(repo)"
    }
}

// MARK: - Session Entity

@Model
final class SessionEntity {
    @Attribute(.unique) var id: String
    var title: String
    var prompt: String
    var stateRaw: String
    var sourceId: String
    var sourceBranch: String
    var automationModeRaw: String
    var requirePlanApproval: Bool
    var createdAt: Date
    var updatedAt: Date
    var prURL: String?
    var prTitle: String?
    var prDescription: String?

    @Relationship(deleteRule: .cascade, inverse: \ActivityEntity.session)
    var activities: [ActivityEntity] = []

    init(
        id: String,
        title: String,
        prompt: String,
        state: SessionState,
        sourceId: String,
        sourceBranch: String,
        automationMode: AutomationMode,
        requirePlanApproval: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.stateRaw = state.rawValue
        self.sourceId = sourceId
        self.sourceBranch = sourceBranch
        self.automationModeRaw = automationMode.rawValue
        self.requirePlanApproval = requirePlanApproval
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(from dto: SessionDTO) {
        self.init(
            id: dto.id,
            title: dto.title ?? "Untitled",
            prompt: dto.prompt,
            state: SessionState(rawValue: dto.state ?? "") ?? .unspecified,
            sourceId: dto.sourceContext?.source ?? "",
            sourceBranch: dto.sourceContext?.githubRepoContext?.startingBranch ?? "main",
            automationMode: AutomationMode(rawValue: dto.automationMode ?? "") ?? .unspecified,
            requirePlanApproval: dto.requirePlanApproval ?? false,
            createdAt: dto.createTime ?? Date(),
            updatedAt: dto.updateTime ?? Date()
        )

        if let output = dto.outputs?.first?.pullRequest {
            self.prURL = output.url
            self.prTitle = output.title
            self.prDescription = output.description
        }
    }

    var state: SessionState {
        SessionState(rawValue: stateRaw) ?? .unspecified
    }

    var automationMode: AutomationMode {
        AutomationMode(rawValue: automationModeRaw) ?? .unspecified
    }
}

// MARK: - Activity Entity

@Model
final class ActivityEntity {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var createdAt: Date
    var contentJSON: Data
    var isOptimistic: Bool
    var sendStatusRaw: String

    var session: SessionEntity?

    init(
        id: String,
        type: ActivityType,
        createdAt: Date,
        contentJSON: Data,
        isOptimistic: Bool = false,
        sendStatus: SendStatus = .sent
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.createdAt = createdAt
        self.contentJSON = contentJSON
        self.isOptimistic = isOptimistic
        self.sendStatusRaw = sendStatus.rawValue
    }

    convenience init(from dto: ActivityDTO) {
        // Use the unified content accessor from the DTO
        let contentData = (try? JSONEncoder().encode(dto.content)) ?? Data()

        self.init(
            id: dto.id,
            type: dto.activityType,
            createdAt: dto.createTime ?? Date(),
            contentJSON: contentData,
            isOptimistic: false,
            sendStatus: .sent
        )
    }

    /// Create an optimistic user message
    convenience init(optimisticMessage: String) {
        let content = ["message": optimisticMessage]
        let contentData = (try? JSONEncoder().encode(content)) ?? Data()

        self.init(
            id: UUID().uuidString,
            type: .userMessaged,
            createdAt: Date(),
            contentJSON: contentData,
            isOptimistic: true,
            sendStatus: .pending
        )
    }

    var type: ActivityType {
        ActivityType(rawValue: typeRaw) ?? .unknown
    }

    var sendStatus: SendStatus {
        SendStatus(rawValue: sendStatusRaw) ?? .sent
    }

    var decodedContent: ActivityContentDTO? {
        try? JSONDecoder().decode(ActivityContentDTO.self, from: contentJSON)
    }

    var messageContent: String? {
        // First try to decode as ActivityContentDTO for full API response structure
        if let content = decodedContent {
            // Return message for user/agent messages
            if let message = content.message {
                return message
            }
            // Return formatted plan steps for plan activities
            if let plan = content.plan, let steps = plan.steps {
                return steps.compactMap { $0.description }.joined(separator: "\n• ")
            }
            // Return progress title or description for progress updates
            if let title = content.progressTitle {
                return title
            }
            if let description = content.progressDescription {
                return description
            }
            // Return progress updates
            if let progress = content.progress {
                return progress
            }
            // Return summary for completed sessions
            if let summary = content.summary {
                return summary
            }
            // Return error for failed sessions
            if let error = content.error {
                return error
            }
        }

        // Fallback: try simple dictionary decode for optimistic messages
        if let dict = try? JSONDecoder().decode([String: String].self, from: contentJSON) {
            return dict["message"]
        }

        return nil
    }

    /// Get bash command executions from this activity
    var bashCommands: [BashOutputDTO] {
        guard let content = decodedContent else {
            return []
        }
        return content.bashCommands
    }

    /// Check if this activity has tool executions
    var hasToolExecutions: Bool {
        !bashCommands.isEmpty
    }

    /// Get the git patch from changeSet artifacts (for session completed activities)
    var gitPatch: GitPatchDTO? {
        guard let content = decodedContent else {
            return nil
        }
        return content.artifacts?.compactMap { $0.changeSet?.gitPatch }.first
    }

    var progressTitle: String? {
        decodedContent?.progressTitle
    }

    var progressDescription: String? {
        decodedContent?.progressDescription
    }

    var plan: PlanDTO? {
        decodedContent?.plan
    }

    /// Get diff stats from git patch
    var diffAdditions: Int {
        gitPatch?.additions ?? 0
    }

    var diffDeletions: Int {
        gitPatch?.deletions ?? 0
    }

    var changedFiles: [String] {
        gitPatch?.changedFiles ?? []
    }
}

enum SessionDisplayState: Equatable {
    case starting
    case queued
    case working
    case awaitingPlanApproval
    case awaitingUserInput
    case completed
    case failed
    case cancelled

    var sessionState: SessionState {
        switch self {
        case .starting:
            return .unspecified
        case .queued:
            return .queued
        case .working:
            return .inProgress
        case .awaitingPlanApproval:
            return .awaitingPlanApproval
        case .awaitingUserInput:
            return .awaitingUserInput
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }
}

enum SessionStateMachine {
    static func resolve(apiState: SessionState, activities: [ActivityEntity]) -> SessionDisplayState {
        let persistedActivities = activities
            .filter { !$0.isOptimistic }
            .sorted { $0.createdAt < $1.createdAt }

        if persistedActivities.isEmpty, activities.contains(where: { $0.isOptimistic && $0.type == .userMessaged }) {
            return .working
        }

        return persistedActivities.reduce(initialState(for: apiState)) { state, activity in
            transition(from: state, with: activity)
        }
    }

    private static func initialState(for apiState: SessionState) -> SessionDisplayState {
        switch apiState {
        case .unspecified:
            return .starting
        case .queued:
            return .queued
        case .running, .inProgress:
            return .working
        case .awaitingPlanApproval:
            return .awaitingPlanApproval
        case .awaitingUserInput:
            return .awaitingUserInput
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    private static func transition(from state: SessionDisplayState, with activity: ActivityEntity) -> SessionDisplayState {
        switch activity.type {
        case .sessionCompleted:
            return .completed
        case .sessionFailed:
            return .failed
        case .planGenerated:
            return .awaitingPlanApproval
        case .planApproved, .progressUpdated, .userMessaged:
            return state == .cancelled ? .cancelled : .working
        case .agentMessaged:
            if state == .completed || state == .failed || state == .cancelled {
                return state
            }

            if requestsUserInput(message: activity.messageContent) {
                return .awaitingUserInput
            }

            switch state {
            case .starting, .queued:
                return .working
            default:
                return state
            }
        case .unknown:
            return state
        }
    }

    private static func requestsUserInput(message: String?) -> Bool {
        guard let message else { return false }
        let normalizedMessage = message.lowercased()

        let phrases = [
            "please clarify",
            "could you",
            "can you confirm",
            "would you like",
            "which would you prefer",
            "let me know",
            "waiting for your input",
            "need your input",
            "before i proceed",
            "reply directly in chat",
        ]

        if phrases.contains(where: normalizedMessage.contains) {
            return true
        }

        if normalizedMessage.filter({ $0 == "?" }).count >= 1 {
            return true
        }

        return normalizedMessage.contains("1.") && normalizedMessage.contains("2.")
    }
}

extension SessionEntity {
    var effectiveDisplayState: SessionDisplayState {
        SessionStateMachine.resolve(apiState: state, activities: activities)
    }

    var effectiveState: SessionState {
        effectiveDisplayState.sessionState
    }

    /// Forward-compatible view of the API state. When Jules ships a new
    /// state we don't yet know about, we render it literally instead of
    /// silently collapsing to `.unspecified` (which used to display as
    /// "Starting" — misleading for sessions in any new lifecycle phase).
    var resolvedState: ResolvedSessionState {
        if SessionState(rawValue: stateRaw) != nil {
            return .known(effectiveState)
        }
        return .unknown(rawValue: stateRaw)
    }

    /// Whether this session has an attached repo. Repoless sessions are
    /// supported by the Jules API today and Jools persists them with an
    /// empty `sourceId` — UI must branch on this rather than show an
    /// empty folder pill.
    var isRepoless: Bool {
        sourceId.isEmpty
    }
}

/// Either a known `SessionState` (with the full state-machine resolution
/// already applied) or a literal raw string returned by the API that we
/// don't recognize yet. The badge knows how to render both — known states
/// pick up their themed colour, unknown ones get a neutral pill with the
/// raw value lightly normalised.
enum ResolvedSessionState: Equatable {
    case known(SessionState)
    case unknown(rawValue: String)

    var displayLabel: String {
        switch self {
        case .known(let state):
            return state.displayName
        case .unknown(let raw):
            return Self.humanize(raw)
        }
    }

    /// Turn an UPPER_SNAKE_CASE API value into a Title Case label.
    private static func humanize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Unknown" }
        return trimmed
            .split(separator: "_")
            .map { word in
                let lowered = word.lowercased()
                return lowered.prefix(1).uppercased() + lowered.dropFirst()
            }
            .joined(separator: " ")
    }
}
