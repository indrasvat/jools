import Foundation
import SwiftData
import JoolsKit

// MARK: - Decoded content cache
//
// Process-wide LRU cache for parsed `ActivityContentDTO` instances,
// keyed on the raw `contentJSON` payload bytes. The previous design
// re-decoded the JSON on every read of `messageContent`, `plan`,
// `bashCommands`, `gitPatch`, `progressTitle`, `progressDescription`,
// `diffAdditions`, `diffDeletions`, and `changedFiles` — a single
// `CompletionCardView` render walked five+ of these accessors and
// triggered five+ JSON decodes per visible cell per layout frame.
// Under sustained chat scroll plus burst-mode polling that became a
// significant main-thread cost (flagged by codex in the 2026-04-07
// council pass).
//
// `NSCache` handles thread-safety and bounded eviction for us. The
// key is `NSData` so two activities with byte-identical payloads
// share the cache slot. When SwiftData mutates `contentJSON` (which
// the idempotent sync only does on actual change), the new payload
// is a different `Data` value and we get a fresh decode entry.
private final class ActivityContentBox {
    let content: ActivityContentDTO
    init(_ content: ActivityContentDTO) { self.content = content }
}

private final class ActivityContentDecodeCache: @unchecked Sendable {
    // `@unchecked Sendable` is correct here: NSCache is documented
    // thread-safe, the boxed `ActivityContentDTO` is immutable after
    // construction, and we only ever write through the
    // `setObject(_:forKey:)` API which has its own internal lock.
    static let shared = ActivityContentDecodeCache()

    private let cache: NSCache<NSData, ActivityContentBox> = {
        let cache = NSCache<NSData, ActivityContentBox>()
        cache.countLimit = 1024
        return cache
    }()

    func decode(from data: Data) -> ActivityContentDTO? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) {
            return cached.content
        }
        guard let decoded = try? JSONDecoder().decode(ActivityContentDTO.self, from: data) else {
            return nil
        }
        cache.setObject(ActivityContentBox(decoded), forKey: key)
        return decoded
    }
}

// MARK: - Source Entity

@Model
final class SourceEntity {
    @Attribute(.unique) var id: String
    /// The full opaque resource name returned by the Jules API
    /// (e.g. `sources/github/indrasvat/namefix`). The API treats this
    /// as the canonical reference; clients must not synthesize it.
    /// Older app versions had `name == id`, so we re-derive on every
    /// dashboard sync to heal in place.
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

        if let pr = dto.outputs?.lazy.compactMap({ $0.pullRequest }).first {
            self.prURL = pr.url
            self.prTitle = pr.title
            self.prDescription = pr.description
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

    /// Returns the parsed `ActivityContentDTO` for this activity,
    /// hitting the process-wide `ActivityContentDecodeCache` so a
    /// repeated read on the same `contentJSON` payload returns in
    /// constant time instead of running `JSONDecoder().decode(...)`
    /// again. The cache key is the raw `Data` value, so when
    /// SwiftData mutates `contentJSON` (which only happens on real
    /// updates under the idempotent sync) the next decode gets a
    /// fresh entry. (Council fix, 2026-04-07.)
    var decodedContent: ActivityContentDTO? {
        ActivityContentDecodeCache.shared.decode(from: contentJSON)
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
    case paused
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
        case .paused:
            return .paused
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
        case .awaitingUserInput, .awaitingUserFeedback:
            return .awaitingUserInput
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .paused:
            return .paused
        case .cancelled:
            return .cancelled
        }
    }

    /// Fold an activity into the current display state.
    ///
    /// Design note: this state machine is deliberately narrow. It trusts
    /// typed activity markers (which are unambiguous) and falls back to
    /// the seeded API state for everything else. It intentionally does
    /// NOT try to infer `awaitingUserInput` by scanning agent message
    /// content — the Jules REST API already returns `AWAITING_USER_INPUT`
    /// as a first-class state; trusting that is strictly better than
    /// substring-matching agent prose, which historically mislabelled
    /// friendly closers ("…just let me know. Have a great day!") as
    /// input-needed.
    private static func transition(from state: SessionDisplayState, with activity: ActivityEntity) -> SessionDisplayState {
        // API-terminal display states are sticky during activity replay:
        // `.cancelled` and `.paused` are user/API-driven hard stops —
        // Jules doesn't resume from them.
        //
        // `.failed` stays sticky (no evidence Jules resumes from a failed
        // session). `.completed`, however, is NOT sticky: when a user
        // follows up on a completed session, Jules re-enters working
        // state and emits new `progressUpdated` / `planGenerated`
        // activities. Those arrive with `createdAt` later than the
        // `.sessionCompleted` marker and (thanks to the sort at
        // line 370) are folded in after it, so flipping the display
        // state back to `.working` / `.awaitingPlanApproval` is
        // genuine re-entry, not replay noise.
        if state == .cancelled || state == .paused { return state }

        switch activity.type {
        case .sessionCompleted:
            return .completed
        case .sessionFailed:
            return .failed
        case .planGenerated:
            // A plan was (re)generated. Unless the session is already
            // in a terminal state, this means Jules is waiting on the
            // user to approve. `.completed` is NOT terminal here — a
            // fresh plan after completion is a re-entry cycle.
            return state == .failed ? state : .awaitingPlanApproval
        case .planApproved:
            // User approved the plan — session is now actively running.
            return state == .failed ? state : .working
        case .progressUpdated:
            // Jules shipped a progress update — definitely working.
            return state == .failed ? state : .working
        case .userMessaged:
            // A user message cancels any "awaiting user input" status
            // and advances starting/queued/completed to working (a
            // follow-up message after completion is re-entry).
            switch state {
            case .failed:
                return state
            case .starting, .queued, .awaitingUserInput, .completed:
                return .working
            default:
                return state
            }
        case .agentMessaged:
            // Advance starting/queued to working on any agent output,
            // but don't second-guess the backend state otherwise —
            // awaitingUserInput comes from the API, not from parsing
            // agent prose.
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
