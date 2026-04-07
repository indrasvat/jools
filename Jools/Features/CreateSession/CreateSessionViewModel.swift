import SwiftUI
import SwiftData
import JoolsKit

/// Session mode matching Jules web UI options
enum SessionMode: String, CaseIterable, Identifiable {
    case interactivePlan = "interactive"
    case review = "review"
    case start = "start"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interactivePlan: return "Interactive plan"
        case .review: return "Review"
        case .start: return "Start"
        }
    }

    var description: String {
        switch self {
        case .interactivePlan:
            return "Chat with Jules to understand goals before planning and approval"
        case .review:
            return "Generate plan and wait for approval"
        case .start:
            return "Get started without plan approval"
        }
    }

    var icon: String {
        switch self {
        case .interactivePlan: return "bubble.left.and.bubble.right"
        case .review: return "doc.text.magnifyingglass"
        case .start: return "play.fill"
        }
    }

    /// Maps to API's requirePlanApproval field
    var requirePlanApproval: Bool {
        switch self {
        case .interactivePlan, .review: return true
        case .start: return false
        }
    }
}

/// View model for creating a new Jules session.
///
/// `source` is optional so the same flow handles both repo-bound
/// sessions and repoless quick-capture tasks. When `source` is nil
/// the branch picker and source header are hidden by the view, and
/// `createSession()` issues a `CreateSessionRequest.repoless(...)`
/// instead of attaching a `sourceContext`.
@MainActor
final class CreateSessionViewModel: ObservableObject {
    // MARK: - State

    @Published var prompt: String = ""
    @Published var title: String = ""
    @Published var selectedBranch: String = "main"
    @Published var availableBranches: [String] = ["main", "master", "develop"]
    @Published var sessionMode: SessionMode = .interactivePlan
    @Published var autoCreatePR: Bool = true

    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showError: Bool = false
    @Published var showModeSheet: Bool = false

    @Published var createdSession: SessionEntity?

    // MARK: - Source Info

    let source: SourceEntity?

    // MARK: - Dependencies

    private var apiClient: APIClient?
    private var modelContext: ModelContext?

    // MARK: - Computed

    var canCreate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var effectiveTitle: String {
        // Trim before deciding which field to use. Previously a
        // whitespace-only `title` ("   ") would pass the isEmpty check
        // and be sent verbatim as the session title. The same treatment
        // applies to `prompt` so the 50-char prefix isn't a wall of
        // leading spaces. (CodeRabbit review.)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? String(trimmedPrompt.prefix(50)) : trimmedTitle
    }

    var sourceDisplayName: String {
        guard let source else { return "Quick task" }
        return "\(source.owner)/\(source.repo)"
    }

    var isRepoless: Bool { source == nil }

    // MARK: - Initialization

    init(
        source: SourceEntity?,
        initialPrompt: String = "",
        initialTitle: String = "",
        initialSessionMode: SessionMode = .interactivePlan
    ) {
        self.source = source
        self.prompt = initialPrompt
        self.title = initialTitle
        self.sessionMode = initialSessionMode
        if source == nil {
            // Repoless tasks can't auto-create a PR (there's no repo to
            // open one against), so default the toggle off.
            self.autoCreatePR = false
        }
    }

    func configure(apiClient: APIClient, modelContext: ModelContext) {
        self.apiClient = apiClient
        self.modelContext = modelContext
    }

    // MARK: - Actions

    func createSession() async {
        guard canCreate, let apiClient, let modelContext else { return }

        isLoading = true
        defer { isLoading = false }

        HapticManager.shared.lightImpact()

        do {
            let request = makeRequest()
            let sessionDTO = try await apiClient.createSession(request)

            // Save to SwiftData. Don't suppress the error — if the
            // local persistence fails, navigating into the new session
            // would land on a row that vanishes on next reload, which
            // is worse than failing visibly here. (CodeRabbit review.)
            let session = SessionEntity(from: sessionDTO)
            modelContext.insert(session)
            try modelContext.save()

            createdSession = session

            HapticManager.shared.success()

        } catch {
            self.error = error.localizedDescription
            self.showError = true
            HapticManager.shared.error()
        }
    }

    private func makeRequest() -> CreateSessionRequest {
        // Normalize the prompt once at the boundary so we never send a
        // trailing-whitespace payload to Jules. `canCreate` already
        // rejects an all-whitespace prompt, so this only strips stray
        // leading/trailing whitespace on an otherwise-valid entry.
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let source else {
            // Repoless quick-capture: no sourceContext, no automation
            // mode (PR creation only makes sense with a repo).
            return CreateSessionRequest.repoless(
                prompt: normalizedPrompt,
                title: effectiveTitle,
                requirePlanApproval: sessionMode.requirePlanApproval
            )
        }

        // Use the opaque server-provided resource name verbatim. The
        // Jules docs are inconsistent about whether ids are bare slugs
        // or full `sources/...` paths, so synthesizing the prefix
        // client-side is a portability hazard. We just forward
        // `source.name` as-is.
        return CreateSessionRequest(
            prompt: normalizedPrompt,
            sourceContext: SourceContextDTO(
                source: source.name,
                githubRepoContext: GitHubRepoContextDTO(startingBranch: selectedBranch)
            ),
            title: effectiveTitle,
            automationMode: autoCreatePR ? "AUTO_CREATE_PR" : nil,
            requirePlanApproval: sessionMode.requirePlanApproval
        )
    }
}
