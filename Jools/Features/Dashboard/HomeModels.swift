import SwiftUI

enum HomeSectionStyle {
    case info
    case success
    case warning
    case error

    var tint: Color {
        switch self {
        case .info:
            return .joolsAccent
        case .success:
            return .joolsSuccess
        case .warning:
            return .joolsAwaiting
        case .error:
            return .joolsFailed
        }
    }

    var background: Color {
        tint.opacity(0.12)
    }
}

struct HomeAttentionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let actionTitle: String
    let sessionID: String
    let style: HomeSectionStyle
}

enum SuggestedTaskCategory: String, CaseIterable, Identifiable {
    case performance
    case testing
    case security
    case codeHealth
    case design

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance:
            return "Performance"
        case .testing:
            return "Testing"
        case .security:
            return "Security"
        case .codeHealth:
            return "Code Health"
        case .design:
            return "Design"
        }
    }

    var icon: String {
        switch self {
        case .performance:
            return "bolt"
        case .testing:
            return "testtube.2"
        case .security:
            return "shield.lefthalf.filled"
        case .codeHealth:
            return "cross.case"
        case .design:
            return "paintpalette"
        }
    }

    var accent: Color {
        switch self {
        case .performance:
            return .joolsAccent
        case .testing:
            return .indigo
        case .security:
            return .joolsSuccess
        case .codeHealth:
            return .orange
        case .design:
            return .pink
        }
    }
}

struct SuggestedTaskTemplate: Identifiable {
    let id: String
    let title: String
    let rationale: String
    let prompt: String
    let confidence: Int
    let category: SuggestedTaskCategory
}

struct ScheduledSkillTemplate: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let cadenceSummary: String
    let details: String
    let prompt: String
    let icon: String
    let accent: Color
}

enum ScheduleCadence: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        }
    }
}

enum HomeContentBuilder {
    static func attentionItems(
        from sessions: [SessionEntity],
        sourcesByID: [String: SourceEntity]
    ) -> [HomeAttentionItem] {
        sessions.compactMap { session in
            let repoName = sourceName(for: session, sourcesByID: sourcesByID)
            switch session.effectiveState {
            case .awaitingPlanApproval:
                return HomeAttentionItem(
                    id: "attention-\(session.id)",
                    title: "Plan approval needed",
                    subtitle: "\(repoName) is waiting for approval before it continues.",
                    actionTitle: "Review plan",
                    sessionID: session.id,
                    style: .warning
                )
            case .awaitingUserInput:
                return HomeAttentionItem(
                    id: "attention-\(session.id)",
                    title: "Jules needs your input",
                    subtitle: "\(repoName) paused until you respond in chat.",
                    actionTitle: "Reply",
                    sessionID: session.id,
                    style: .warning
                )
            case .failed:
                return HomeAttentionItem(
                    id: "attention-\(session.id)",
                    title: "Session failed",
                    subtitle: "\(repoName) hit an error and needs inspection.",
                    actionTitle: "Inspect",
                    sessionID: session.id,
                    style: .error
                )
            case .inProgress:
                return HomeAttentionItem(
                    id: "attention-\(session.id)",
                    title: "Work in progress",
                    subtitle: "\(repoName) is actively running in the background.",
                    actionTitle: "Check status",
                    sessionID: session.id,
                    style: .info
                )
            case .running:
                return HomeAttentionItem(
                    id: "attention-\(session.id)",
                    title: "Work in progress",
                    subtitle: "\(repoName) is actively running in the background.",
                    actionTitle: "Check status",
                    sessionID: session.id,
                    style: .info
                )
            default:
                return nil
            }
        }
        .prefix(3)
        .map { $0 }
    }

    static func suggestedTasks(for source: SourceEntity) -> [SuggestedTaskTemplate] {
        [
            SuggestedTaskTemplate(
                id: "performance-\(source.id)",
                title: "Diagnose the highest-impact performance drag",
                rationale: "Ask Jules for one measurable win and a bounded fix.",
                prompt: "Inspect the \(source.repo) codebase and identify one small, measurable performance improvement. Explain the bottleneck first, propose a safe fix, and keep any code changes narrowly scoped.",
                confidence: 4,
                category: .performance
            ),
            SuggestedTaskTemplate(
                id: "testing-\(source.id)",
                title: "Backfill the highest-value missing regression test",
                rationale: "Useful when recent fixes feel under-protected.",
                prompt: "Review the \(source.repo) repository for one high-value missing regression test. Explain why it matters, implement only the smallest useful coverage, and avoid unrelated changes.",
                confidence: 3,
                category: .testing
            ),
            SuggestedTaskTemplate(
                id: "code-health-\(source.id)",
                title: "Remove stale debug code and noisy branches",
                rationale: "A low-risk cleanup pass that improves signal for future work.",
                prompt: "Inspect the \(source.repo) repository for a small code health improvement, such as stale debug logging, unreachable branches, or dead helpers. Choose one safe cleanup and explain the reasoning before making changes.",
                confidence: 3,
                category: .codeHealth
            ),
        ]
    }

    static func scheduledTemplates(for source: SourceEntity) -> [ScheduledSkillTemplate] {
        [
            ScheduledSkillTemplate(
                id: "bolt-\(source.id)",
                name: "Bolt",
                subtitle: "Performance",
                cadenceSummary: "Daily tune-up",
                details: "One bounded improvement with measurement and verification.",
                prompt: "Inspect the \(source.repo) codebase and deliver one small, measurable performance improvement. Measure the current issue first, keep the change tightly scoped, and verify the improvement before finishing.",
                icon: "bolt.circle.fill",
                accent: .joolsAccent
            ),
            ScheduledSkillTemplate(
                id: "palette-\(source.id)",
                name: "Palette",
                subtitle: "Design",
                cadenceSummary: "Weekly polish",
                details: "A small UX, accessibility, or visual refinement.",
                prompt: "Inspect the \(source.repo) codebase and deliver one small UX or accessibility improvement. Focus on a visible quality issue, keep the change easy to review, and explain the user-facing impact.",
                icon: "paintpalette.fill",
                accent: .indigo
            ),
            ScheduledSkillTemplate(
                id: "sentinel-\(source.id)",
                name: "Sentinel",
                subtitle: "Security",
                cadenceSummary: "Daily safeguard",
                details: "A narrow security fix or hardening improvement.",
                prompt: "Inspect the \(source.repo) codebase and address one small security issue or hardening improvement. Prioritize the highest-value low-risk fix, explain the risk clearly, and keep the implementation bounded.",
                icon: "shield.checkerboard",
                accent: .joolsSuccess
            ),
        ]
    }

    static func sourceName(for session: SessionEntity, sourcesByID: [String: SourceEntity]) -> String {
        if session.isRepoless {
            return "This task"
        }

        if let source = sourcesByID[session.sourceId] {
            return source.repo
        }

        let normalized = session.sourceId
            .replacingOccurrences(of: "sources/", with: "")
            .split(separator: "/")
            .last
            .map(String.init)

        return normalized ?? "This repo"
    }
}
