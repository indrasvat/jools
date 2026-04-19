# Sessions scenario harness

Multi-step integration tests that drive the real `ChatViewModel` +
real SwiftData stack against a mock `URLSession`, the way a user
would drive the app over minutes — not the single-action unit tests
in `JoolsTests.swift`.

## Why this exists

Every Sessions bug shipped this quarter was caught *after* user
report, not by the existing tests:

- Stuck "Session completed" banner on re-entry
- Banner "Pull to refresh" unreachable
- 874 MB `listActivities` timeout → infinite `.stale` loop
- Re-fetched full history on every manual refresh

Unit tests for `SessionStateMachine` and snapshot dedupe catch
narrow invariants, but they don't catch the *interactions* — polling
resuming after a sync failure, cursor drift after a recovery, banner
reacting to new activities mid-polling cycle. Those need a test that
acts like a user over many steps.

## Architecture

- **`ScenarioHarness`** — orchestrator. Sets up an in-memory
  `ModelContainer`, wires a real `APIClient` to a scripted
  `MockURLProtocol`, constructs a real `ChatViewModel`, and exposes
  verbs (`runStep`, `expect`, `advanceTime`) for writing scenarios.
- **`MockResponseQueue`** — scripted sequence of HTTP responses.
  Each request pops the next response; assertions can inspect the
  request URL / query to ensure the client sent what we expect.
- **Scenarios** — one Swift file per scenario (`*Scenario.swift`
  under `Scenarios/`), each declares a `@Suite` or `@Test` that
  uses the harness.

## Scenarios we need (prioritised)

1. **Staleness recovery** — session with persisted activities; API
   times out on the first list request; a subsequent retry uses the
   cursor and succeeds; banner moves `.stale` → `.idle`; new
   activities render. *Would have caught PR #20's bug.*
2. **Completion re-entry** — session ends with `sessionCompleted`;
   polling continues; new `progressUpdated` activity arrives;
   `session.effectiveState` transitions back to `.working`; banner
   stops showing "Session completed". *Would have caught PR #20's
   bug.*
3. **Plan approval + follow-up** — plan generated → user approves →
   plan approved → work progresses → session completes. Asserts
   state machine walks through all the right states and the snapshot
   stream has the correct kinds in the correct order (including
   dedupe of the known duplicate `planApproved` from the REST API).
4. **Fields mask contract** — verifies that every `listActivities`
   request the view model emits carries the `fields=` query param
   and omits `unidiffPatch`. *Pins PR #20's byte-level fix.*
5. **Foreground / background** — polling pauses on background,
   resumes on foreground with a fresh poll tick, no missed activities
   during the suspension window.
6. **Navigation continuity** — `ChatViewModel.teardown` cancels
   in-flight refresh tasks; re-entering the view starts a clean
   polling loop without duplicate fetches.

## Non-goals (keep scope small)

- **No XCUITest here.** Simulator flakiness + TimelineView races make
  UI-level scenarios unreliable on CI. We exercise the view model +
  SwiftData + `APIClient` stack, which is where the bugs this quarter
  actually lived. One-off UI regressions can live in `JoolsUITests/`
  as they do now.
- **No real network.** Every scenario is deterministic via
  `MockURLProtocol`.
- **No "run for X seconds" tests.** Scenarios step through state
  transitions by direct control; `ScenarioHarness.advanceTime` fast-
  forwards timers without sleeping so CI doesn't pay wall-clock cost.

## Adding a new scenario

1. Create `Scenarios/<Name>Scenario.swift`.
2. `@MainActor` test func that builds the harness, scripts the
   response queue, runs the viewmodel through the steps, asserts
   on `viewModel.syncState`, `session.effectiveState`, the activity
   count, etc.
3. If the scenario adds a new fixture shape, park it in
   `Fixtures/` next to the existing JSON captures.

## Status

- [x] Directory created + this README
- [ ] `ScenarioHarness` + `MockResponseQueue` scaffolding
- [ ] First scenario: staleness recovery (covers PR #20 root cause)
- [ ] Plumb into `make test-app` target
- [ ] Remaining scenarios (2–6 above)
