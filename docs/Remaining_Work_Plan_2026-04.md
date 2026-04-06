## Jools Remaining Work Plan

Last updated: April 6, 2026

### Current state

Jools is now a solid unofficial iOS client for the public Jules API surface:

- authentication and API-key onboarding work
- sources sync works
- sessions list and session detail work
- follow-up messaging works
- session sync and recovery are much more reliable
- `Home` is now a meaningful mobile control plane
- dark mode is dynamic and visually verified
- `Scheduled` has a native composer and a polished in-app Jules web handoff

Jools is not yet full product parity with `jules.google.com`.

### Hard API boundary

The public Jules REST API currently exposes:

- `sources`
- `sessions`
- `sessions.activities`

It does not currently expose first-class REST support for:

- scheduled-task CRUD
- suggestions feed
- CI Fixer management
- Render integration management
- MCP / integrations management
- repo overview metadata beyond what can be inferred from sessions and sources

That means anything in those areas has to use one of two strategies:

1. Native UI plus web handoff
2. Custom Jools-owned integrations and backend logic

### Answer to the CI Fixer / Render / integration question

Yes. With the public API as it exists today, native CI Fixer / Render / integrations support would require custom work outside the Jules REST API.

There are only three realistic approaches:

- web handoff into the official Jules UI
- a custom Jools backend that talks directly to GitHub, Render, or other providers and presents Jools-owned status/actions
- leaving those features out of scope until the public Jules API supports them

The cleanest near-term answer is web handoff.

The cleanest long-term answer, if this becomes important, is a Jools-owned integration layer.

### Product direction

Jools should keep leaning into the mobile-control-plane thesis:

- triage
- delegation
- approvals
- lightweight catch-up
- recurring automation setup
- calm, glanceable state

It should not try to become a cramped replica of the full desktop Jules web interface.

## Phase 1: Finish the scheduled handoff experience

### Goal

Make `Scheduled` feel complete and intentional even though creation still finishes in the web UI.

### Build

- keep the new native `Scheduled Task` composer
- add a tiny inline status after returning from Safari:
  - `Created`
  - `Not yet created`
  - `Try again`
- add optional helper copy:
  - `Open Scheduled`
  - `Choose Performance / Design / Security`
  - `Paste the prompt if needed`
- add a subtle load state while `SFSafariViewController` is opening
- add repo-aware continuation copy everywhere, not generic Jules wording
- preserve the chosen cadence and branch in the return state for confirmation and retry

### Test

- launch the app from a clean simulator state
- go to `Home`
- scroll to `Scheduled`
- open each preset composer:
  - `Performance`
  - `Design`
  - `Security`
- verify:
  - preset title
  - cadence summary
  - branch field
  - `Continue in Jules`
  - `Copy Prompt`
  - `Open Repo`
- tap `Continue in Jules`
- confirm:
  - in-app Safari opens
  - clipboard contains the expected prompt
  - repo path is correct
- dismiss Safari
- confirm return sheet appears and is legible in both light and dark
- repeat once in `namefix` and once in `hews`

### Done criteria

- the flow feels native and deliberate
- clipboard handoff is reliable
- return state is clear
- screenshots look good in light and dark

## Phase 2: Repo detail surface

### Goal

Introduce a repo-level screen that matches Jules’s conceptual model without copying the web layout.

### Build

- create a repo detail screen with:
  - `Overview`
  - `Suggested`
  - `Scheduled`
- `Overview`:
  - compact repo health snapshot
  - recent sessions
  - quick actions
- `Suggested`:
  - native suggestion rows
  - category icon
  - confidence bars
  - `Start`
  - `Why`
  - `Dismiss`
- `Scheduled`:
  - current presets
  - future placeholder for recurring tasks once API support exists or a bridge is added

### Constraint

True suggestion-feed parity is not possible from the public API today. So v1 here should use:

- curated native bootstrap suggestions
- recent session heuristics
- future adapter seam for real upstream suggestions if/when available

### Test

- verify navigation into repo detail from `Home`
- test all three segments in light and dark
- verify content density on iPhone portrait only first
- ensure large titles, nav transitions, and empty states remain crisp
- compare live repo context against the official web UI for `hews` and `namefix`

### Done criteria

- repo detail feels useful on phone
- `Suggested` and `Scheduled` have clear roles
- there is no dead-end repo screen

## Phase 3: Sessions as an inbox

### Goal

Turn `Sessions` from a simple history list into a useful mobile inbox.

### Build

- add filters:
  - `Active`
  - `Waiting`
  - `Done`
  - `Failed`
- better row metadata:
  - active step
  - awaiting approval
  - awaiting user input
  - completed
- add quick actions where API allows:
  - open
  - refresh
  - retry sync
- preserve current thread state and never regress into blank screens

### Test

- use real `hews` sessions
- verify state changes during:
  - running
  - plan approval
  - user input request
  - completed follow-up
- background and foreground the app
- verify session list and detail remain in sync with the web UI within one normal refresh cycle

### Done criteria

- `Sessions` answers “what needs me now?”
- users can triage from the list without opening every thread

## Phase 4: Notifications and attention flow

### Goal

Make Jools useful when the app is not already open.

### Build

- local notification settings screen
- groundwork for push-style attention model
- in-app attention states:
  - `Needs approval`
  - `Needs input`
  - `Completed`
  - `Failed`

### Constraint

Real remote push depends on either:

- your own Jools service
- or future upstream API/webhook support

Without that, only local or foreground refresh-based notifications are possible.

### Test

- verify settings copy and toggles
- verify badge/attention UI in `Home`
- verify no false urgency in calm states

### Done criteria

- Jools starts feeling like a real mobile control plane rather than a passive viewer

## Phase 5: Native review and artifact surfaces

### Goal

Improve what users can actually inspect on phone after Jules finishes work.

### Build

- richer final-answer rendering
- artifact list for files/media when the API exposes them via session activities
- diff-summary cards if precise diff rendering is not yet feasible
- PR linkouts with clear context

### Constraint

Full native PR/code-review parity is still limited by what the Jules REST API exposes and what is practical on phone.

### Test

- use completed real sessions with artifacts when available
- compare Jools rendering against the web session page
- verify readability in light and dark

### Done criteria

- users can understand results without always going back to the web UI

## Phase 6: Optional custom integration layer

### Goal

Decide whether Jools should remain a pure Jules client or become a broader mobile agent-control app.

### Option A: stay pure

- only implement what the public Jules API exposes
- use elegant web handoff for everything else

### Option B: add Jools-owned integrations

Build a small service that talks to:

- GitHub
- Render
- other providers

And then expose native Jools features such as:

- CI status and failures
- deployment failures
- PR readiness
- recurring repo maintenance workflows

This would be valuable, but it is no longer just “a Jules client”.

### Recommendation

Choose `A` for now.

Revisit `B` only if Jools starts proving real daily-use value and the missing surfaces become a clear product bottleneck.

## Verification strategy for all remaining work

### Simulator verification

For every shipped slice:

- run from a clean simulator state
- verify `Home`, `Sessions`, and `Settings`
- verify light and dark
- verify onboarding/empty/loaded states where relevant
- capture screenshots for:
  - initial state
  - active interaction state
  - success state
  - failure or empty state

### Live Jules parity checks

For any feature touching real product semantics:

- compare against the authenticated Jules web UI in Chrome Beta
- use the same repo on both sides
- prefer `hews` and `namefix` for repeatable validation
- verify:
  - terminology
  - action order
  - state meaning
  - missing capabilities due API boundaries

### Repeated real-world test cases

- reopen a completed session and send a follow-up
- inspect a running session in parallel with the web UI
- open a scheduled composer and hand off to Jules web
- create a short-lived scheduled task in the web UI for validation
- dismiss Safari and verify return state in Jools
- switch light/dark during active use

### UI/UX review checklist

- typography stays legible on phone-sized widths
- cards remain distinct in light and dark
- primary actions are always visually dominant
- touch targets are generous and obvious
- no important state relies on color alone
- tab bar remains readable over all content states
- sheets do not feel cramped or overlong

## Suggested next implementation order

1. finish scheduled handoff polish
2. build repo detail with `Overview / Suggested / Scheduled`
3. upgrade `Sessions` into a real inbox
4. add stronger attention and notification model
5. improve result/review surfaces
6. reassess whether custom integrations are worth building
