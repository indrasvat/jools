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

    @Test("Snapshot builder collapses adjacent planApproved duplicates")
    @MainActor
    func snapshotBuilderCollapsesAdjacentPlanApproved() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .planApproved, createdAt: base, content: ActivityContentDTO()),
            makeActivity(id: "a2", type: .planApproved, createdAt: base.addingTimeInterval(30), content: ActivityContentDTO())
        ]

        let snapshots = ActivitySnapshotBuilder.build(from: activities, fallback: [])

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.kind == .planApproved)
    }

    @Test("State machine re-enters working when progress arrives after completion")
    func stateMachineReentersWorkingAfterCompletion() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .sessionCompleted, createdAt: base, content: ActivityContentDTO(summary: "Done")),
            makeActivity(
                id: "a2",
                type: .progressUpdated,
                createdAt: base.addingTimeInterval(60),
                content: ActivityContentDTO(progress: "Resuming work", progressTitle: "Fixing", progressDescription: nil)
            )
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .completed, activities: activities)

        #expect(resolvedState == .working)
    }

    @Test("State machine re-enters plan approval when plan regenerated after completion")
    func stateMachineReentersAwaitingApprovalAfterCompletion() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .sessionCompleted, createdAt: base, content: ActivityContentDTO(summary: "Done")),
            makeActivity(
                id: "a2",
                type: .planGenerated,
                createdAt: base.addingTimeInterval(90),
                content: ActivityContentDTO(plan: PlanDTO(id: "p1", steps: []))
            )
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .completed, activities: activities)

        #expect(resolvedState == .awaitingPlanApproval)
    }

    @Test("State machine stays completed when no activities follow")
    func stateMachineStaysCompletedAtTail() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .planApproved, createdAt: base, content: ActivityContentDTO()),
            makeActivity(
                id: "a2",
                type: .progressUpdated,
                createdAt: base.addingTimeInterval(10),
                content: ActivityContentDTO(progress: "Working", progressTitle: "Working", progressDescription: nil)
            ),
            makeActivity(id: "a3", type: .sessionCompleted, createdAt: base.addingTimeInterval(20), content: ActivityContentDTO(summary: "Done"))
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .completed, activities: activities)

        #expect(resolvedState == .completed)
    }

    @Test("State machine keeps failed sticky even if progress follows")
    func stateMachineFailedStaysSticky() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .sessionFailed, createdAt: base, content: ActivityContentDTO(message: "Boom")),
            makeActivity(
                id: "a2",
                type: .progressUpdated,
                createdAt: base.addingTimeInterval(30),
                content: ActivityContentDTO(progress: "noise", progressTitle: "noise", progressDescription: nil)
            )
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .failed, activities: activities)

        #expect(resolvedState == .failed)
    }

    @Test("State machine re-enters working when user follows up after completion")
    func stateMachineUserFollowupReentersWorking() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .sessionCompleted, createdAt: base, content: ActivityContentDTO(summary: "Done")),
            makeActivity(
                id: "a2",
                type: .userMessaged,
                createdAt: base.addingTimeInterval(30),
                content: ActivityContentDTO(message: "actually, wait — can you also...")
            )
        ]

        let resolvedState = SessionStateMachine.resolve(apiState: .completed, activities: activities)

        #expect(resolvedState == .working)
    }

    @Test("Snapshot builder preserves non-adjacent planApproved entries")
    @MainActor
    func snapshotBuilderPreservesNonAdjacentPlanApproved() throws {
        let base = Date()
        let activities = [
            makeActivity(id: "a1", type: .planApproved, createdAt: base, content: ActivityContentDTO()),
            makeActivity(
                id: "a2",
                type: .planGenerated,
                createdAt: base.addingTimeInterval(10),
                content: ActivityContentDTO(plan: PlanDTO(id: "p1", steps: []))
            ),
            makeActivity(id: "a3", type: .planApproved, createdAt: base.addingTimeInterval(20), content: ActivityContentDTO())
        ]

        let snapshots = ActivitySnapshotBuilder.build(from: activities, fallback: [])

        #expect(snapshots.count == 3)
        #expect(snapshots.filter { $0.kind == .planApproved }.count == 2)
    }

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
