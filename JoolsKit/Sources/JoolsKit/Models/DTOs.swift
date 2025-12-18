import Foundation

// MARK: - Source DTOs

/// A GitHub repository connected to Jules
public struct SourceDTO: Codable, Sendable, Identifiable {
    public let name: String
    public let id: String
    public let githubRepo: GitHubRepoDTO
}

/// GitHub repository details
public struct GitHubRepoDTO: Codable, Sendable {
    public let owner: String
    public let repo: String
    public let isPrivate: Bool?
    public let defaultBranch: BranchDTO?
    public let branches: [BranchDTO]?
}

/// Branch information
public struct BranchDTO: Codable, Sendable {
    public let displayName: String
}

// MARK: - Session DTOs

/// A coding session in Jules
public struct SessionDTO: Codable, Sendable, Identifiable {
    public let name: String
    public let id: String
    public let title: String?
    public let prompt: String
    public let state: String?
    public let sourceContext: SourceContextDTO?
    public let automationMode: String?
    public let requirePlanApproval: Bool?
    public let outputs: [SessionOutputDTO]?
    public let createTime: Date?
    public let updateTime: Date?
}

/// Source context for a session
public struct SourceContextDTO: Codable, Sendable {
    public let source: String
    public let githubRepoContext: GitHubRepoContextDTO?

    public init(source: String, githubRepoContext: GitHubRepoContextDTO?) {
        self.source = source
        self.githubRepoContext = githubRepoContext
    }
}

/// GitHub repository context
public struct GitHubRepoContextDTO: Codable, Sendable {
    public let startingBranch: String?

    public init(startingBranch: String?) {
        self.startingBranch = startingBranch
    }
}

/// Session output (e.g., pull request)
public struct SessionOutputDTO: Codable, Sendable {
    public let pullRequest: PullRequestDTO?
}

/// Pull request details
public struct PullRequestDTO: Codable, Sendable {
    public let url: String
    public let title: String
    public let description: String?
}

// MARK: - Activity DTOs

/// An activity within a session - matches Jules API polymorphic format
public struct ActivityDTO: Codable, Sendable, Identifiable {
    public let name: String
    public let id: String
    public let createTime: Date?
    public let originator: String?

    // Polymorphic activity content - only one will be present
    public let agentMessaged: AgentMessagedDTO?
    public let userMessaged: UserMessagedDTO?
    public let planGenerated: PlanGeneratedDTO?
    public let planApproved: PlanApprovedDTO?
    public let progressUpdated: ProgressUpdatedDTO?
    public let sessionCompleted: SessionCompletedDTO?
    public let sessionFailed: SessionFailedDTO?

    // Artifacts attached to the activity (tool executions, file changes)
    public let artifacts: [ArtifactDTO]?

    /// Computed activity type based on which field is present
    public var activityType: ActivityType {
        if agentMessaged != nil { return .agentMessaged }
        if userMessaged != nil { return .userMessaged }
        if planGenerated != nil { return .planGenerated }
        if planApproved != nil { return .planApproved }
        if progressUpdated != nil { return .progressUpdated }
        if sessionCompleted != nil { return .sessionCompleted }
        if sessionFailed != nil { return .sessionFailed }
        return .unknown
    }

    /// Legacy type string for compatibility
    public var type: String {
        activityType.rawValue
    }

    /// Unified content accessor for compatibility
    public var content: ActivityContentDTO {
        ActivityContentDTO(
            message: agentMessaged?.agentMessage ?? userMessaged?.userMessage,
            plan: planGenerated?.plan,
            progress: progressUpdated?.progressUpdate,
            progressTitle: progressUpdated?.title,
            progressDescription: progressUpdated?.description,
            summary: sessionCompleted?.summary,
            error: sessionFailed?.error,
            artifacts: artifacts
        )
    }
}

/// Agent message content
public struct AgentMessagedDTO: Codable, Sendable {
    public let agentMessage: String?
}

/// User message content
public struct UserMessagedDTO: Codable, Sendable {
    public let userMessage: String?
}

/// Plan generated content
public struct PlanGeneratedDTO: Codable, Sendable {
    public let plan: PlanDTO?
}

/// Plan approved content
public struct PlanApprovedDTO: Codable, Sendable {
    public let planId: String?
}

/// Progress update content
public struct ProgressUpdatedDTO: Codable, Sendable {
    public let progressUpdate: String?
    public let title: String?
    public let description: String?
}

/// Artifact attached to an activity (tool executions, file changes)
public struct ArtifactDTO: Codable, Sendable {
    public let bashOutput: BashOutputDTO?
    public let changeSet: ChangeSetDTO?
}

/// Bash command execution result
public struct BashOutputDTO: Codable, Sendable {
    public let command: String?
    public let output: String?
    public let exitCode: Int?

    /// Infer if the command likely failed based on output patterns
    public var isLikelyFailure: Bool {
        // If we have an explicit exit code, use it
        if let code = exitCode, code != 0 {
            return true
        }

        // Otherwise infer from output patterns
        guard let output = output?.lowercased() else { return false }

        let failurePatterns = [
            "error:",
            "error ",
            "failed",
            "not found",
            "command not found",
            "no such file",
            "permission denied",
            "fatal:",
            "exception",
            "segmentation fault",
            "killed",
            "abort"
        ]

        return failurePatterns.contains { output.contains($0) }
    }
}

/// Git change set
public struct ChangeSetDTO: Codable, Sendable {
    public let source: String?
    public let gitPatch: GitPatchDTO?
}

/// Git patch details
public struct GitPatchDTO: Codable, Sendable {
    public let baseCommitId: String?
    public let patch: String?
}

/// Session completed content
public struct SessionCompletedDTO: Codable, Sendable {
    public let summary: String?
}

/// Session failed content
public struct SessionFailedDTO: Codable, Sendable {
    public let error: String?
}

/// Activity content (unified structure for compatibility)
public struct ActivityContentDTO: Codable, Sendable {
    public let message: String?
    public let plan: PlanDTO?
    public let progress: String?
    public let progressTitle: String?
    public let progressDescription: String?
    public let summary: String?
    public let error: String?
    public let artifacts: [ArtifactDTO]?

    public init(
        message: String? = nil,
        plan: PlanDTO? = nil,
        progress: String? = nil,
        progressTitle: String? = nil,
        progressDescription: String? = nil,
        summary: String? = nil,
        error: String? = nil,
        artifacts: [ArtifactDTO]? = nil
    ) {
        self.message = message
        self.plan = plan
        self.progress = progress
        self.progressTitle = progressTitle
        self.progressDescription = progressDescription
        self.summary = summary
        self.error = error
        self.artifacts = artifacts
    }

    /// Extract bash commands from artifacts
    public var bashCommands: [BashOutputDTO] {
        artifacts?.compactMap { $0.bashOutput } ?? []
    }
}

/// Plan details
public struct PlanDTO: Codable, Sendable {
    public let id: String?
    public let steps: [PlanStepDTO]?
}

/// A step in a plan
public struct PlanStepDTO: Codable, Sendable {
    public let id: String?
    public let title: String?
    public let description: String?
    public let status: String?
    public let index: Int?
}

// MARK: - Request DTOs

/// Request to create a new session
public struct CreateSessionRequest: Codable, Sendable {
    public let prompt: String
    public let sourceContext: SourceContextDTO
    public let title: String?
    public let automationMode: String?
    public let requirePlanApproval: Bool?

    public init(
        prompt: String,
        sourceContext: SourceContextDTO,
        title: String? = nil,
        automationMode: String? = nil,
        requirePlanApproval: Bool? = nil
    ) {
        self.prompt = prompt
        self.sourceContext = sourceContext
        self.title = title
        self.automationMode = automationMode
        self.requirePlanApproval = requirePlanApproval
    }
}

/// Request to send a message in a session
public struct SendMessageRequest: Codable, Sendable {
    public let prompt: String

    public init(prompt: String) {
        self.prompt = prompt
    }
}

// MARK: - Response DTOs

/// Paginated response wrapper
public struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    public let sessions: [T]?
    public let sources: [T]?
    public let activities: [T]?
    public let nextPageToken: String?

    /// Get all items regardless of which key they're under
    public var allItems: [T] {
        sessions ?? sources ?? activities ?? []
    }
}

/// Empty response for endpoints that don't return data
public struct EmptyResponse: Codable, Sendable {}

// MARK: - Enums

/// Session states
public enum SessionState: String, Codable, Sendable, CaseIterable {
    case unspecified = "SESSION_STATE_UNSPECIFIED"
    case queued = "QUEUED"
    case running = "RUNNING"
    case inProgress = "IN_PROGRESS"  // API uses IN_PROGRESS instead of RUNNING
    case awaitingUserInput = "AWAITING_USER_INPUT"
    case awaitingPlanApproval = "AWAITING_PLAN_APPROVAL"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    public var displayName: String {
        switch self {
        case .unspecified: return "Starting"
        case .queued: return "Queued"
        case .running, .inProgress: return "Running"
        case .awaitingUserInput: return "Needs Input"
        case .awaitingPlanApproval: return "Needs Approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    public var isActive: Bool {
        switch self {
        case .unspecified, .queued, .running, .inProgress, .awaitingUserInput, .awaitingPlanApproval:
            return true
        default:
            return false
        }
    }
}

/// Automation modes
public enum AutomationMode: String, Codable, Sendable {
    case unspecified = "AUTOMATION_MODE_UNSPECIFIED"
    case autoCreatePR = "AUTO_CREATE_PR"
}

/// Activity types
public enum ActivityType: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case planGenerated = "PLAN_GENERATED"
    case planApproved = "PLAN_APPROVED"
    case userMessaged = "USER_MESSAGED"
    case agentMessaged = "AGENT_MESSAGED"
    case progressUpdated = "PROGRESS_UPDATED"
    case sessionCompleted = "SESSION_COMPLETED"
    case sessionFailed = "SESSION_FAILED"
}

/// Message send status for optimistic UI
public enum SendStatus: String, Codable, Sendable {
    case pending
    case sent
    case failed
}
