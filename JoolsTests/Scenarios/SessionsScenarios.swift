import Foundation
import Testing
@testable import Jools
@testable import JoolsKit

/// Sessions scenarios — multi-step integration tests that drive the
/// real `ChatViewModel` + `APIClient` + SwiftData stack through the
/// flows that have caused user-visible bugs. One `@Suite(.serialized)`
/// to keep the shared `ScenarioURLProtocol.queue` deterministic
/// across scenarios; new scenarios go here rather than in separate
/// suites so swift-testing's per-suite parallelism doesn't stomp the
/// queue.
@Suite("Sessions scenarios", .serialized)
struct SessionsScenarios {

    @Test("Staleness recovery: timeout → retry via cursor → idle")
    @MainActor
    func stalenessRecovery() async throws {
        let harness = try ScenarioHarness(
            sessionId: "586903571471720369",
            sessionTitle: "Diagnose the highest-impact performance drag",
            initialState: .inProgress
        )

        // First request: the getSession call. Respond with a minimal
        // session shape so performRefresh can proceed to the activity
        // fetch (the actual bug is in listActivities, not getSession).
        harness.responses.respond(json: minimalSessionJSON)

        // Second request: the listActivities call times out — mirrors
        // the 60s URLSession default timeout blowing out on an 874 MB
        // response.
        harness.responses.fail(with: .timedOut) { request in
            #expect(request.url?.path.hasSuffix("/activities") == true)
            // Initial load has no cursor so no createTime= is present.
            let query = request.url?.query ?? ""
            #expect(query.contains("createTime=") == false)
            // The fields= mask must always be present (PR #20 invariant).
            #expect(query.contains("fields="))
        }

        await harness.loadActivities()

        // Banner should be `.stale` with persisted activities (none
        // yet — no successful fetch has landed). `.failed` is the
        // expected state when hasPersistedActivities() is false.
        try await harness.awaitSyncState(.failed(message: ""))
        #expect(harness.session.activities.isEmpty)

        // Now retry. Queue a getSession success + a successful
        // listActivities response with two activities. Since there's
        // nothing persisted yet the client will NOT use the cursor —
        // it's a no-cursor initial-load retry path.
        harness.responses.respond(json: minimalSessionJSON)
        harness.responses.respond(json: activitiesJSON(activities: [
            ActivityFixture(id: "act-1", type: "USER_MESSAGED", message: "what are the top perf drags?", createTime: "2026-04-18T20:00:00Z"),
            ActivityFixture(id: "act-2", type: "AGENT_MESSAGED", message: "Inspecting the codebase now.", createTime: "2026-04-18T20:00:30Z"),
        ])) { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("fields="))
            // No persisted cursor, so no createTime= on this retry.
            #expect(query.contains("createTime=") == false)
        }

        await harness.manualRefresh()

        try await harness.awaitSyncState(.idle)
        try await harness.awaitActivityCount(2)
        #expect(harness.responses.unexpectedCount == 0)
    }

    @Test("Incremental refresh uses cursor once activities exist")
    @MainActor
    func incrementalRefreshUsesCursor() async throws {
        let harness = try ScenarioHarness(
            sessionId: "session-abc",
            initialState: .inProgress
        )

        // First fetch lands two activities — this populates the
        // persisted timeline so the next refresh can cursor.
        harness.responses.respond(json: minimalSessionJSON)
        harness.responses.respond(json: activitiesJSON(activities: [
            ActivityFixture(id: "a1", type: "USER_MESSAGED", message: "go", createTime: "2026-04-18T20:00:00Z"),
            ActivityFixture(id: "a2", type: "AGENT_MESSAGED", message: "on it", createTime: "2026-04-18T20:00:10Z"),
        ]))

        await harness.loadActivities()
        try await harness.awaitActivityCount(2)

        // Second fetch MUST include `createTime=` because there are
        // persisted activities. This is the PR #20 cursor-always fix.
        let cursorFlag = AssertionFlag()
        harness.responses.respond(json: minimalSessionJSON) { request in
            // getSession — should NOT carry createTime.
            #expect(request.url?.query?.contains("createTime=") != true)
        }
        harness.responses.respond(json: activitiesJSON(activities: [
            ActivityFixture(id: "a3", type: "PROGRESS_UPDATED", message: "Running tests", createTime: "2026-04-18T20:01:00Z"),
        ])) { request in
            let query = request.url?.query ?? ""
            if request.url?.path.hasSuffix("/activities") == true {
                #expect(query.contains("createTime="), "cursor must be used once activities are persisted")
                #expect(query.contains("fields="))
                cursorFlag.set()
            }
        }

        await harness.manualRefresh()
        try await harness.awaitActivityCount(3)
        #expect(cursorFlag.value)
    }

    // MARK: - Completion re-entry (PR #20 state-machine fix)

    @Test("Completion re-entry: sessionCompleted → user follow-up → working")
    @MainActor
    func completionReentry() async throws {
        let harness = try ScenarioHarness(
            sessionId: "reentry-session",
            initialState: .inProgress
        )

        // Initial load: session + single sessionCompleted activity.
        harness.responses.respond(json: sessionJSON(id: "reentry-session", state: "COMPLETED"))
        harness.responses.respond(json: completedActivityJSON(
            id: "done-1",
            createTime: "2026-04-18T20:00:00Z",
            summary: "Done"
        ))
        await harness.loadActivities()
        try await harness.awaitActivityCount(1)
        #expect(harness.session.effectiveDisplayState == .completed)

        // Follow-up refresh: server reports back to IN_PROGRESS and
        // two new activities (user message + progress update).
        harness.responses.respond(json: sessionJSON(id: "reentry-session", state: "IN_PROGRESS"))
        harness.responses.respond(json: activitiesJSON(activities: [
            ActivityFixture(id: "user-1", type: "USER_MESSAGED", message: "one more thing", createTime: "2026-04-18T20:01:00Z"),
            ActivityFixture(id: "prog-1", type: "PROGRESS_UPDATED", message: "Reopening", createTime: "2026-04-18T20:01:10Z"),
        ]))
        await harness.manualRefresh()
        try await harness.awaitActivityCount(3)

        // State machine must move .completed → .working because
        // later progressUpdated arrived.
        #expect(harness.session.effectiveDisplayState == .working)
    }

    @Test("Failed stays sticky even if new progress arrives")
    @MainActor
    func failedStickyOnReentry() async throws {
        let harness = try ScenarioHarness(
            sessionId: "failed-session",
            initialState: .failed
        )

        harness.responses.respond(json: sessionJSON(id: "failed-session", state: "FAILED"))
        harness.responses.respond(json: failedActivityJSON(
            id: "fail-1",
            createTime: "2026-04-18T20:00:00Z",
            error: "Boom"
        ))
        await harness.loadActivities()
        try await harness.awaitActivityCount(1)
        #expect(harness.session.effectiveDisplayState == .failed)

        // Stray progress after a failure must NOT unstick .failed.
        harness.responses.respond(json: sessionJSON(id: "failed-session", state: "FAILED"))
        harness.responses.respond(json: activitiesJSON(activities: [
            ActivityFixture(id: "p-1", type: "PROGRESS_UPDATED", message: "noise", createTime: "2026-04-18T20:01:00Z"),
        ]))
        await harness.manualRefresh()
        try await harness.awaitActivityCount(2)
        #expect(harness.session.effectiveDisplayState == .failed)
    }
}

// MARK: - Helpers

/// Thread-safe Bool flag for assertions inside mock-request closures
/// that run on the URL-loading queue (outside the test's actor).
final class AssertionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    func set() { lock.lock(); _value = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
}

// MARK: - JSON fixtures (inline to keep scenarios self-contained)

private let minimalSessionJSON = """
{
  "name": "sessions/586903571471720369",
  "id": "586903571471720369",
  "title": "Diagnose the highest-impact performance drag",
  "prompt": "diagnose",
  "state": "IN_PROGRESS",
  "createTime": "2026-04-18T19:00:00Z",
  "updateTime": "2026-04-18T20:00:00Z"
}
"""

struct ActivityFixture {
    let id: String
    let type: String
    let message: String
    let createTime: String
}

private func sessionJSON(id: String, state: String) -> String {
    """
    {
      "name": "sessions/\(id)",
      "id": "\(id)",
      "title": "Scenario session",
      "prompt": "p",
      "state": "\(state)",
      "createTime": "2026-04-18T19:00:00Z",
      "updateTime": "2026-04-18T20:00:00Z"
    }
    """
}

private func completedActivityJSON(id: String, createTime: String, summary: String) -> String {
    """
    {"activities":[{
      "name": "sessions/s/activities/\(id)",
      "id": "\(id)",
      "createTime": "\(createTime)",
      "originator": "agent",
      "sessionCompleted": {"summary": "\(summary)"}
    }]}
    """
}

private func failedActivityJSON(id: String, createTime: String, error: String) -> String {
    """
    {"activities":[{
      "name": "sessions/s/activities/\(id)",
      "id": "\(id)",
      "createTime": "\(createTime)",
      "originator": "agent",
      "sessionFailed": {"error": "\(error)"}
    }]}
    """
}

private func activitiesJSON(activities: [ActivityFixture]) -> String {
    let items = activities.map { a -> String in
        let payload: String
        switch a.type {
        case "USER_MESSAGED":
            payload = "\"userMessaged\": {\"userMessage\": \"\(a.message)\"}"
        case "AGENT_MESSAGED":
            payload = "\"agentMessaged\": {\"agentMessage\": \"\(a.message)\"}"
        case "PROGRESS_UPDATED":
            payload = "\"progressUpdated\": {\"progressUpdate\": \"\(a.message)\", \"title\": \"\(a.message)\"}"
        default:
            payload = "\"userMessaged\": {\"userMessage\": \"\(a.message)\"}"
        }
        return """
        {
          "name": "sessions/s1/activities/\(a.id)",
          "id": "\(a.id)",
          "createTime": "\(a.createTime)",
          "originator": "user",
          \(payload)
        }
        """
    }.joined(separator: ",")
    return "{\"activities\":[\(items)]}"
}
