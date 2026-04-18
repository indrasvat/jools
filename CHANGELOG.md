# Changelog

All notable changes to Jataayu are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The headline section for each release reflects what a user would actually
notice. The "Internal" subsection captures architectural and infrastructure
work that doesn't change behaviour but matters for future maintenance.

## [Unreleased]

### Fixed

- **Duplicate "Plan approved" row in chat history.** The Jules REST
  API emits two `planApproved` activities per approval (same
  `planId`, ~30s apart); the web UI shows only one. Adjacent
  duplicates are now collapsed at the snapshot layer so Jataayu
  matches the web UI.

## [1.2.3] — 2026-04-14

### Internal

- **Export compliance auto-handled.** Added
  `ITSAppUsesNonExemptEncryption=false` to Info.plist so App Store
  Connect uploads no longer prompt for "Missing Compliance".
- **Release process fixed.** Generated `project.pbxproj` is now
  included in release commits (was causing dirty working tree after
  every tag).
- **Main branch protected.** Required status checks (SwiftLint,
  JoolsKit, iOS app) must pass before merging. Force pushes and
  branch deletion blocked.

## [1.2.2] — 2026-04-14

### Fixed

- **Onboarding "Connect to Jules" now works reliably.** The in-app
  Safari browser had no Google session, so the Jules landing page
  hid the sign-in button below the fold. Now opens in system Safari
  via Google AccountChooser, landing directly on the API settings
  page when already signed in.

## [1.2.1] — 2026-04-14

### Fixed

- **Session progress events now visible.** Intermediate events (file
  updates, test results, code reviews) that were rendering as blank
  gaps in the timeline now show as compact expandable cards with
  markdown-formatted descriptions.
- **PR link displayed in completion card.** Sessions that produce a
  pull request now show a "View PR" button and "Copy URL" action in
  the completion card. Root cause: the app only checked the first
  API output; the PR was in the second.
- **Completion card redesigned.** Layout now matches the Jules web UI
  "Ready for review" card: header with diff stats, commit message,
  scrollable file pills, approximate duration, and PR section.
- **Plan steps are expandable.** Each step in the Proposed Plan card
  now shows a chevron to reveal the full description.
- **Nested markdown renders correctly.** Bold, code, and links inside
  list items no longer show as literal `**text**` markers.
- **Faster notification delivery.** Background polling interval
  reduced from 15 to 5 minutes, and the app now checks for session
  transitions immediately on returning to foreground.

## [1.2.0] — 2026-04-14

### Changed

- Renamed app from Jools to **Jataayu** — after the sentinel eagle of the Ramayana. New tagline: "Watch over Jules."
- Updated bundle identifier from `com.indrasvat.jools` to `com.indrasvat.jataayu`

## [1.1.0] — 2026-04-13

### Added

- **Local notifications for session state changes.** Jools now posts
  iOS notifications when a session needs plan approval, needs user
  input, completes, or fails. Custom "duo" chime sound. Foreground
  suppression when you're already viewing the session.
  `UNUserNotificationCenterDelegate` handles tap-to-navigate (warm
  and cold launch). Background App Refresh polls the Jules API when
  the app is suspended (~15-60 min intervals).
- **Notification permission primer.** On the first notifiable session
  transition, a branded "Stay in the loop" sheet asks for permission
  instead of a cold system dialog on first launch.
- **Enhanced notification settings.** Permission status indicator
  (green/red), per-category toggles (Plan & Input, Completed,
  Failed), and a link to system Settings when permission is denied.
- **Keychain accessibility upgraded** from `kSecAttrAccessibleWhenUnlocked`
  to `kSecAttrAccessibleAfterFirstUnlock` so background refresh can
  authenticate on locked devices. Transparent one-time migration.

- **Animated in-bubble Jules avatar.** The mascot next to agent
  message bubbles now gently bobs with a time-driven sine wave
  (±2pt amplitude, 2.4s period) that matches the Jules web UI
  reference frame-by-frame. Implemented via `TimelineView(.animation)`
  so the motion is phase-locked to the system clock and never
  stutters on parent re-renders.
- **Onboarding feature pills — 5 total.** Added `Triage inbox` and
  `Quick capture` alongside the existing `Approve plans`,
  `Chat with Jules`, and `View diffs`. Reading order is
  load-bearing: Triage + Quick capture describe what Home does the
  moment you sign in; the other three describe what you do once
  you open a session.
- **Animated indeterminate progress strip** along the bottom edge
  of the session status banner for active states (running, queued,
  unspecified). Two sine-phase-offset gradient bands sweeping
  left→right on a 2.0s linear cycle — industry-standard
  indeterminate-progress pattern (GitHub, Linear, Xcode, Safari).

### Changed

- **Onboarding copy refresh** to match what the app actually ships:
  `Review PRs` → `View diffs` (we render diffs, we don't gate PR
  review), `Live progress` → `Chat with Jules` (sessions are
  fully interactive, not just a status feed).
- **Session status banner redesign** (active states only). The
  bouncing mascot was overshooting the banner's top edge in real
  running sessions; removed entirely. The leading spinner and the
  trailing "Live" pill were also removed — both were redundant
  with the title text, the animated ellipsis dots, and the new
  progress strip. The title `"Jules is working…"` is now flush-left
  with a larger font (`.subheadline` → `.title3`). Banner for
  terminal / awaiting states (completed, failed, cancelled,
  awaiting input, awaiting plan approval) is unchanged.
- **In-bubble agent avatar** — the circular gradient backdrop + stroke
  border around the pixel mascot was removed. The pixel mascot IS
  the avatar now. Spacing between the avatar and the message bubble
  was bumped from `JoolsSpacing.sm` (12pt) to `JoolsSpacing.md`
  (16pt) so the avatar reads as "next to" the bubble, not "glued to".

### Fixed

- **Regression in the snapshot architecture: file-pill → DiffViewerView
  navigation was silently dropped** during the Option B migration
  (`FilePill` in `CompletionRow` had an empty closure). Restored by
  parsing the unified-diff patch eagerly in
  `ActivitySnapshotBuilder`, carrying the parsed `diffFiles` on
  `CompletionSnapshot`, and presenting `DiffViewerView` as a sheet
  when a file pill is tapped.
- **UI test flakiness (`testRunningSessionScreenShowsRecoveryChrome`).**
  The test was using `app.descendants(matching: .any)["chat.scroll"]`
  — a whole-tree query that regularly blew the 30s snapshot
  timeout on GitHub's macos-15 runners, wedging the simulator and
  cascading into "Failed to terminate" / "Failed to launch" errors
  on every subsequent test in the suite. Dropped the assertion
  (the surrounding specific assertions cover the same ground).
- **UI test flakiness (`testSessionScreenSurvivesBackgroundForeground`).**
  Post-`app.activate()` accessibility queries sometimes return
  before the snapshot is fresh, especially on slow CI runners.
  Switched the checks from synchronous `.exists` to
  `.waitForExistence(timeout:)`.
- **Paste button behaviour.** Documented the iOS 16+ privacy
  dialog's "Don't Allow Paste" default button trap; existing
  button still works after the user explicitly allows paste, but
  the pattern is noted in `docs/LEARNINGS.md` for a future switch
  to SwiftUI `PasteButton`.

### Internal

- **`TimelineView`-based animation pattern** for continuous periodic
  motion (replacing the `@State + .animation(.repeatForever)`
  pattern in `JulesAvatarView` and the new
  `IndeterminateProgressStrip`). Documented in `docs/LEARNINGS.md`.
- **`docs/LEARNINGS.md`** captures the hard lessons from the chat
  freeze saga, CI speedup false starts, mascot animation calibration,
  simulator hygiene, and iOS platform quirks so future sessions
  don't re-pay the same tuition.
- **`CLAUDE.md` + `AGENTS.md`** — agent-oriented repo guide with
  progressive-disclosure sections for chat / animation / CI /
  release / simulator workflows, plus a session close-out
  checklist that keeps `docs/LEARNINGS.md` up to date.
- **Release pipeline refactor (`scripts/ci-release`)** — all shell
  logic extracted from `.github/workflows/release.yml` into a
  single shellchecked script with subcommand dispatch (`parse`,
  `verify`, `notes`, `build`, `package`, `publish`). Smoke-tested
  end-to-end via the `v1.0.0-alpha.1` tag.
- **Pre-release tag support** added to the release workflow and
  `ci-release` script: the tag's numeric portion is compared
  against `MARKETING_VERSION`, CHANGELOG extraction falls back to
  the numeric entry if no dedicated pre-release entry exists, and
  the resulting GitHub Release is marked `--prerelease` when the
  tag carries a suffix.
- **README screenshots (all 10)** refreshed from the latest build
  against a real authenticated Jules session, showing the new
  onboarding pills, banner design, and avatar treatment.

## [1.0.0] — 2026-04-08

The first public release of Jools — an unofficial iOS client for Google's
[Jules](https://jules.google/) cloud coding agent. Everything below ships
end-to-end against the public Jules REST API; no self-hosted backend, no
private endpoints.

### Added

#### Authentication and onboarding

- Onboarding flow that opens an in-app Safari sheet against
  `jules.google.com`, watches the clipboard for an API key on return, and
  offers to use it automatically.
- Manual API key entry sheet for users who prefer to paste directly.
- Keychain-backed key storage via `KeychainManager` with proper error
  handling for missing / unreadable items.
- Light/dark mode support across the entire onboarding flow.

#### Home dashboard

- "Needs Attention" summary section that surfaces sessions waiting on plan
  approval, user input, or recovery action.
- Suggested tasks section (currently sourced from a curated set, since the
  public API doesn't yet expose a suggestions endpoint).
- Scheduled tasks section that hands off to the official Jules web flow for
  CRUD (no public API for scheduled tasks yet).
- Today's usage tile showing session count against the daily limit.
- Pull-to-refresh that respects a 15-second throttle on tab reappearance to
  avoid hammering the API.
- Dynamic theming that follows the system appearance plus an in-app theme
  override (System / Light / Dark) persisted across launches.

#### Sessions

- Sessions list view with swipe-to-delete plus a confirmation alert.
- Per-session detail screen with the full activity timeline: agent
  messages, user messages, plan generation, progress updates, completion
  summaries, and failure messages.
- Adaptive polling via `PollingService` that uses the Jules API's
  `createTime` filter for incremental fetches with a graceful fallback if
  the backend rejects it. Polling cadence shifts based on whether the app
  is foregrounded and whether the session is actively running.
- Optimistic send for follow-up messages: the user's bubble appears
  instantly in the chat, then reconciles with the server-side activity
  once Jules acknowledges it.
- Plan approval card with expandable steps and `Approve` / `Revise`
  buttons. Approving transitions the session straight to `running` even
  before the next polling tick lands.
- Session status banner that maps the API's session state to a calm,
  contextual headline plus a "Live" indicator when polling is active.
- Per-file diff viewer for completed sessions, parsed from the
  `unidiffPatch` field in the API response. Shows additions, deletions,
  and unchanged context.
- Diff stats and changed-file pills on the completion card with a
  copy-PR-URL action when a pull request was opened.
- Session creation flow with a CreateSession composer that supports both
  source-bound and "repoless" quick-capture sessions.

#### Chat surface

- Markdown rendering for agent messages, including paragraphs, headings,
  ordered/unordered lists, blockquotes, code blocks (monospaced, scrollable),
  tables, thematic breaks, and inline markup (bold, italic, code, links).
- Auto-scroll to the latest activity when opening a session and when new
  messages arrive.
- Pixel-art Jules mascot avatar shown in the status banner with subtle
  breathing animation, matching the in-bubble avatar so the chat surface
  presents one consistent visual for Jules.
- Animated "Jules is working…" banner with three-state ellipsis dots and a
  stable accessibility label so VoiceOver and UI tests don't flake on the
  visual animation.
- Keyboard dismisses automatically after sending a message.

#### Settings

- Theme picker with live preview.
- Build info display (git SHA, branch, build date) injected at build time
  by an Xcode run-script phase.
- Delete-all-data action that clears the SwiftData store and revokes the
  Keychain entry.

### Internal

- **JoolsKit** Swift package: `APIClient` actor that wraps the Jules REST
  endpoints, `Endpoints` enum, `NetworkError` taxonomy with
  cancellation-aware silencing, `DiffParser` for unidiff parsing,
  `KeychainManager` for token storage, and `PollingService` for adaptive
  background polling.
- **SwiftData** persistence layer with `Source`, `Session`, and `Activity`
  entities, kept in sync with the API via `idempotent` reconciliation
  passes that compare before mutating to avoid spurious save churn.
- **Snapshot architecture** for the chat surface: `ActivitySnapshot`
  value-type wrappers eliminate `@PersistedProperty` access from view
  bodies. The chat list now hosts a SwiftUI `List` (UICollectionView under
  the hood) instead of a `LazyVStack`, so cell recycling kicks in instead
  of remeasurement on every layout invalidation.
- **Flat markdown renderer** that packs paragraphs / headings / lists /
  blockquotes into a single `AttributedString` and only spawns separate
  views for code blocks, tables, and thematic breaks. Reduces a typical
  agent message from ~50 nested SwiftUI views to ~4 flat segments.
- `ChatViewModel` migrated from `ObservableObject` + `@Published` to
  `@Observable` (Swift 5.9+) so per-property tracking lets SwiftUI skip
  re-rendering for unrelated state changes.
- Process-wide `MarkdownDocumentCache` and `ActivityContentDecodeCache`
  via `NSCache` so repeated parses on the same source return in constant
  time.
- Strict Swift 6 concurrency mode (`SWIFT_STRICT_CONCURRENCY=complete`)
  across the entire project.
- XcodeGen-driven `project.yml` so the Xcode project file is generated
  rather than tracked, eliminating merge conflicts.
- `Makefile` with targets for build, test, lint, simulator control,
  bootstrap, JoolsKit isolation, and a full local CI pipeline.
- `lefthook.yml` pre-push hook that runs `make lint` + `make kit-build`.
- GitHub Actions CI workflow with three parallel jobs: SwiftLint,
  JoolsKit (build + test), iOS app (build + test).
- `bootstrap` shell script that installs SwiftLint, XcodeGen, Lefthook,
  and xcpretty, then runs `make generate`.
- `JoolsTests` (unit) + `JoolsUITests` (XCUITest) covering the state
  machine, persistence, key onboarding, dashboard sections, plan
  approval, session recovery, theme switching, and chat surface
  rendering.
- Comprehensive design system: `JoolsColors`, `JoolsSpacing`,
  `JoolsRadius`, `JoolsTypography`, `Appearance`, `Haptics`.

### Known limitations

The following are upstream constraints (no public API), not unimplemented
work in Jools:

- No in-app scheduled-task CRUD — handed off to the Jules web UI.
- No suggestions feed beyond a curated starter set.
- No CI Fixer / Render / MCP integration management.
- Media-artifact viewer covers only `bashOutput` and `changeSet` types.
- No remote push notifications.

[Unreleased]: https://github.com/indrasvat/jataayu/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/indrasvat/jataayu/releases/tag/v1.0.0
