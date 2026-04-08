# Changelog

All notable changes to Jools are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The headline section for each release reflects what a user would actually
notice. The "Internal" subsection captures architectural and infrastructure
work that doesn't change behaviour but matters for future maintenance.

## [Unreleased]

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

[Unreleased]: https://github.com/indrasvat/jools/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/indrasvat/jools/releases/tag/v1.0.0
