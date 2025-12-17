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
}

// MARK: - Session DTOs

/// A coding session in Jules
public struct SessionDTO: Codable, Sendable, Identifiable {
    public let name: String
    public let id: String
    public let title: String?
    public let prompt: String
    public let state: String?
    public let sourceContext: SourceContextDTO
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

/// An activity within a session
public struct ActivityDTO: Codable, Sendable, Identifiable {
    public let name: String
    public let id: String
    public let type: String
    public let createTime: Date?
    public let content: ActivityContentDTO?
}

/// Activity content (flexible structure)
public struct ActivityContentDTO: Codable, Sendable {
    public let message: String?
    public let plan: PlanDTO?
    public let progress: String?
    public let summary: String?
    public let error: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        plan = try container.decodeIfPresent(PlanDTO.self, forKey: .plan)
        progress = try container.decodeIfPresent(String.self, forKey: .progress)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case message, plan, progress, summary, error
    }
}

/// Plan details
public struct PlanDTO: Codable, Sendable {
    public let steps: [PlanStepDTO]?
}

/// A step in a plan
public struct PlanStepDTO: Codable, Sendable {
    public let description: String?
    public let status: String?
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
    case awaitingUserInput = "AWAITING_USER_INPUT"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    public var displayName: String {
        switch self {
        case .unspecified: return "Unknown"
        case .queued: return "Queued"
        case .running: return "Running"
        case .awaitingUserInput: return "Needs Input"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    public var isActive: Bool {
        switch self {
        case .queued, .running, .awaitingUserInput:
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
