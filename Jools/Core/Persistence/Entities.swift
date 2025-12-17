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
            sourceId: dto.sourceContext.source,
            sourceBranch: dto.sourceContext.githubRepoContext?.startingBranch ?? "main",
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
        let contentData: Data
        if let content = dto.content {
            contentData = (try? JSONEncoder().encode(content)) ?? Data()
        } else {
            contentData = Data()
        }

        self.init(
            id: dto.id,
            type: ActivityType(rawValue: dto.type) ?? .unknown,
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

    var messageContent: String? {
        guard let dict = try? JSONDecoder().decode([String: String].self, from: contentJSON) else {
            return nil
        }
        return dict["message"]
    }
}
