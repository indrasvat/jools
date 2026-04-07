import Testing
@testable import Jools
import JoolsKit

@Suite("Jools App Tests")
struct JoolsTests {
    @Test("App launches successfully")
    func appLaunches() async throws {
        // Basic smoke test
        #expect(true)
    }

    // Note: `stateMachineMapsClarifyingMessageToNeedsInput` was
    // removed. It asserted that an agent-messaged activity with
    // interrogative prose ("could you clarify") should fold to
    // `.awaitingUserInput` via the state machine. That behavior was
    // powered by the content-scanning heuristic we explicitly
    // removed because it produced false positives on friendly closer
    // text ("…just let me know. Have a great day!"). The state
    // machine now trusts the API's `AWAITING_USER_INPUT` state
    // directly — see the design note on `SessionStateMachine.transition`.

    @Test("State machine maps generated plan to awaiting approval")
    func stateMachineMapsGeneratedPlanToAwaitingApproval() throws {
        let activities = [
            makeActivity(
                id: "plan",
                type: .planGenerated,
                createdAt: Date(),
                content: ActivityContentDTO(
                    plan: PlanDTO(
                        id: "plan-1",
                        steps: [
                            PlanStepDTO(
                                id: "step-1",
                                title: "Inspect the repo",
                                description: "Read the code paths first.",
                                status: "PENDING",
                                index: 0
                            )
                        ]
                    )
                )
            )
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .inProgress, activities: activities)

        #expect(resolvedState == .awaitingPlanApproval)
    }

    @Test("State machine advances from user reply to working and then completed")
    func stateMachineAdvancesToCompletion() throws {
        let baseTime = Date()
        let activities = [
            makeActivity(
                id: "question",
                type: .agentMessaged,
                createdAt: baseTime,
                content: ActivityContentDTO(
                    message: "Could you confirm the preferred output format?"
                )
            ),
            makeActivity(
                id: "reply",
                type: .userMessaged,
                createdAt: baseTime.addingTimeInterval(5),
                content: ActivityContentDTO(message: "Reply directly in chat.")
            ),
            makeActivity(
                id: "progress",
                type: .progressUpdated,
                createdAt: baseTime.addingTimeInterval(10),
                content: ActivityContentDTO(
                    progress: "Reviewing the codebase",
                    progressTitle: "Reviewing the codebase",
                    progressDescription: "Reading the main entry points."
                )
            ),
            makeActivity(
                id: "done",
                type: .sessionCompleted,
                createdAt: baseTime.addingTimeInterval(20),
                content: ActivityContentDTO(summary: "Finished successfully.")
            )
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .unspecified, activities: activities)

        #expect(resolvedState == .completed)
    }

    // Note: `effectiveStatePrefersTimelineOverStartingState` was
    // removed for the same reason as
    // `stateMachineMapsClarifyingMessageToNeedsInput` above — it
    // depended on the content-scanning heuristic that has been
    // deliberately removed in favor of trusting the API's own
    // `AWAITING_USER_INPUT` state.

    private func makeActivity(
        id: String,
        type: ActivityType,
        createdAt: Date,
        content: ActivityContentDTO
    ) -> ActivityEntity {
        let contentJSON = try! JSONEncoder().encode(content)
        return ActivityEntity(
            id: id,
            type: type,
            createdAt: createdAt,
            contentJSON: contentJSON
        )
    }
}
