# Chat Surface Freeze — Analysis and UIKit Migration Plan

**Status:** Diagnostic complete, pivot recommended.
**Date:** 2026-04-07
**Author:** Claude Code (in collaboration with @indrasvat) + dootsabha council (codex + gemini)

---

## 1. Executive Summary

The Jools chat surface has hit four distinct freeze patterns under sustained scroll on a polling-active session. Each round of fixes has *materially reduced* main-thread render cost (peak: 97% → 1.7% in instrumented samples) but **the freeze keeps coming back in a different shape**. The pattern is the SwiftUI LazyVStack signature problem: variable-height markdown bubbles, observation-driven invalidation, and SwiftData @PersistedProperty keypath access combine to produce an O(N) per-layout-pass cost that no amount of "tweak the SwiftUI bits" can fully eliminate.

**Recommendation:** Pivot the chat message list (`ChatMessagesList`) to UIKit (`UICollectionView` + `UICollectionViewDiffableDataSource`). Keep everything else SwiftUI. Estimated cost: 6–8 hours of focused work. Eliminates the freeze category structurally rather than chasing leaves.

This document is the full case for the pivot, the migration plan, the risks, and the feature-parity checklist.

---

## 2. Observed Freezes — Forensic Timeline

### Freeze #1 — Polling task chain re-entrancy
**Commits:** `ceedf63` (initial fix) → `1b2e190` (full fix)
**Reproduction:** Plan-revise → approve → first agent message starts streaming → app hard-freeze, must force-kill.
**Sample evidence:** Not captured at the time (real-device freeze, no `sample` available). Diagnosis was via dootsabha council pass on the source code.

**Root cause:** `PollingService.requestPoll` had a `defer { Task { … } }` re-entrant pattern. `triggerImmediatePoll` spawned a separate `Task` for the immediate poll *while* `restartPollingLoop` simultaneously kicked off a new sleep-then-poll cycle. Both fought for the single `pollInFlight` slot, the loser set `queuedReason`, and the in-flight poll's defer block spawned yet another `Task` to drain the queue. Under burst-mode (1Hz polling post plan-approval) the chain grew unboundedly and saturated the @MainActor queue.

**Fix:** Rewrote the polling loop as a single task that polls-first-then-sleeps. Drop duplicate poll requests entirely (the next scheduled tick will pick up any new state in 1–3s). Removed `queuedReason`, removed `activateBurstMode` helper. Plus: removed `triggerStaleRecoveryIfNeeded` from the delegate path (it was firing a redundant `getSession + listAllActivities` round-trip on every state change).

**Status after fix:** Confirmed eliminated in simulator stress test. The polling task chain is no longer a contributor.

---

### Freeze #2 — LazyVStack measurement loop
**Commits:** Through `8bbd2f6`
**Reproduction:** Sustained scroll on a running session with active polling and N markdown bubbles.

**Sample evidence (5s window, frozen Jools process):**

```
4074 main thread total samples
3958 in ViewGraphRootValueUpdater.render            (97.2%)
3960 in CA::Layer::layout_and_display_if_needed
3963 in _UIHostingView.layoutSubviews
~190 samples per LazyVStackLayout.sizeThatFits chain (multiple chains visible)
~150 samples in key path getter for ActivityEntity.id
```

**Diagnosis (dootsabha council, codex + gemini):** Both agents independently identified:
1. `ChatViewModel.syncActivities` and `updateSession` writing to entities and calling `modelContext.save()` on every poll regardless of whether data changed → fires `@Query` invalidation → re-runs `ChatView.body` → re-walks LazyVStack → re-measures every visible markdown cell.
2. `ChatView.body` reading `viewModel.isPolling`, `syncState`, `lastSuccessfulSyncAt`, all of which flip multiple times per poll cycle → multiple parent re-evaluations per second.
3. `ActivityEntity.contentJSON` being JSON-decoded on every read of `messageContent`, `plan`, `bashCommands`, `gitPatch`, etc. — a single CompletionCardView render walks 5+ accessors, each triggering a fresh decode.
4. Banner dot timer (0.4s) and typing dot timer (0.3s) firing UI updates continuously.
5. `SessionEntity.effectiveState` walking the entire activity timeline through the state machine on every body invocation.

**Fixes shipped:**
- **`a473b90` and `8bbd2f6`:** Document parsing cache (NSCache) for markdown.
- **`8bbd2f6`:** Hoisted `effectiveState` and `resolvedState` to a single `let` at top of body, threaded through children as parameters.
- **Idempotent SwiftData sync** in `syncActivities` and `updateSession` (compare DTO field against entity, only mutate on actual change, only save if at least one mutation).
- **`ChatMessagesList` extracted** as a child view that owns its own `@Query`.

**Sample evidence after fix (5-minute mixed stress test, all-fixes axe-driven build):**

| Sample window | Total samples | Render% | Idle% | LazyVStack hits |
|---|---|---|---|---|
| BROKEN (5s) | 4074 | **97.2%** | ~0% | many |
| FIXED axe (30s) | 25521 | **9.9%** | 81.3% | 0 |
| FIXED manual (60s) | 50812 | **5.5%** | 87.4% | 0 |
| FIXED fresh-session 5min (90s) | 75982 | **1.7%** | 87.8% | 0 |

**Numerical victory of ~57× reduction** in main-thread render time. The user's manual repro path no longer triggered the LazyVStack measurement loop in instrumented testing.

**BUT — the user re-reported freeze on their next session.**

---

### Freeze #3 — `_UIHostingView.beginTransaction → UpdateStack::update → _ZStackLayout.placeSubviews`
**State after Freeze #2 fixes** (binary md5 confirmed via simulator install)
**Reproduction:** User scrolling a fresh repoless session with active polling.

**Sample evidence:**

```
4118 main thread total
4061 in _UIHostingView.beginTransaction → updateGraph → flushTransactions
     → runTransaction → Subgraph::update → UpdateStack::update      (98.6%)
275  → LazySubviewPlacements.updateValue → placeSubviews            (6.7% within)
LazyVStackLayout.sizeThatFits hits: 0                               ← previous fix held
```

**The bottleneck shifted.** `LazyVStack.sizeThatFits` is gone, but `_UIHostingView.beginTransaction` and `_ZStackLayout.placeSubviews` are now the dominant frames. SwiftUI is doing many synchronous immediate transaction updates, each forcing a full layout pass.

**Diagnosis (second dootsabha council pass with codex):**

> "`ChatView.body` reads `viewModel.syncState`, `viewModel.isPolling`, `viewModel.lastSuccessfulSyncAt` to pass them as parameters to `SessionStatusBanner`. With `@Observable`, every property read inside a body establishes per-property tracking. The parent body invalidates on every poll tick despite the children being extracted into separate views. The fix: move the volatile reads INTO their own tiny child views so the parent never reads them at all."

**Fixes shipped (commit `a473b90` + `2730287`):**
- **Migrated `ChatViewModel` from `ObservableObject` + `@Published` to `@Observable`** so per-property tracking replaced object-wide invalidation.
- **`@ObservationIgnored`** on all non-view-facing internals (`logger`, `apiClient`, `modelContext`, `pollingService`, `sessionId`, `cancellables`, tasks, `lastStaleRecoveryAt`, `isConfigured`).
- **Tiny observer wrapper views**:
  - `LiveChatChrome` — owns ALL session-state derivation (effectiveState, resolvedState, currentStep text, latestProgressActivity, latestPlanStep). The parent body never reads `session.activities` or any session-derived computed property.
  - `LiveSessionStatusBanner` — reads `viewModel.syncState`, `isPolling`, `lastSuccessfulSyncAt`, wraps the stateless `SessionStatusBanner`.
  - `MessageSentConfirmationOverlay` — reads `viewModel.messageSentConfirmation`.
  - `ErrorAlertHost` (ViewModifier) — reads `viewModel.error`, `showError`.
  - `RefreshToolbarButton` — reads `viewModel.isSyncing`.
- **`ChatMessagesList`** computes its own `effectiveState` and `canRespondToPlan` internally; no longer takes them as parameters.
- **`configure()` is idempotent** via `isConfigured` guard so repeated `onAppear` doesn't stack Combine subscriptions.
- **`pollingService.$isPolling` pipeline has `.removeDuplicates()`** so identical-value writes don't trigger Observable notifications.
- **`teardown()` method** called from `ChatView.onDisappear` cancels refresh tasks, optimistic reconciliation tasks, drops the polling delegate, clears cancellables, resets `isConfigured`.
- **`ActivityContentDecodeCache`** — process-wide NSCache for parsed `ActivityContentDTO` (1024-entry cap), eliminating repeated `JSONDecoder().decode()` calls per cell render.

**Council verdict on the v2 fix:**

> *codex:* "Your third pass is materially correct. I do not see a hidden observation mistake that would keep the old freeze alive. The remaining observation reads are either stable (`session.id`, `viewModel` reference) or isolated into smaller children. This version is very likely to fix the dispatchImmediately freeze you were seeing."

**Status:** Built, installed (md5 verified), tested via stress harness — **and the user STILL hit the freeze on a fresh repoless session.**

---

### Freeze #4 — Current state (after v2)
**Build:** Confirmed v2 via md5 (`a56bdae1cc7eb240497dab9d58d84c5c`)
**Monitor:** v2 freeze detector running, fired **11 consecutive freeze alerts** at 100% main-thread busy.

**Sample evidence (5s window of frozen process):**

```
4164 main thread total                                            (~833 samples/sec)
4164 in mach_msg_overwrite under non-main thread (idle bg)
   0 in mach_msg_overwrite under main thread                      ← MAIN IS BUSY
4164 in _UIHostingView.beginTransaction chain                     (100%)
3659 in runTransaction
3455 in Subgraph::update
2916 in UpdateStack::update
```

**Leaf work in deepest frames:**
```
286   LazyLayoutViewCache.updateItemPhases
252   LazySubviewPlacements.updateValue
237   UnaryChildGeometry.value.getter / LayoutEngineBox.childPlacement
235   UnaryLayoutEngine.childPlacement / _FrameLayout.placement
218   StackLayout.sizeThatFits chains
~60+  key path getter for ActivityEntity.id → ActivityEntity.id.getter
      → persistentBackingData.getter → outlined init with copy of any BackingData
```

**The picture:** with all the OTHER costs eliminated, the dominant work is now the SwiftUI layout system itself walking the LazyVStack on every layout pass — `_FrameLayout.placement`, `StackLayout.sizeThatFits`, `LazyLayoutViewCache.updateItemPhases`. AND the `ActivityEntity.id` keypath getter is back as a leaf cost because the `ForEach(activities, id: \.id)` call still goes through SwiftData's observation registrar for cell identity resolution on every layout frame.

**Total fix budget exhausted on the SwiftUI side.** The remaining cost is intrinsic to LazyVStack + variable-height markdown content + SwiftData @Model entities in the ForEach. There is no further @Observable or NSCache trick that addresses it.

---

## 3. Complete Fix Inventory (Commits)

| Commit | Title | Status |
|---|---|---|
| `1b2e190` | fix(chat): eliminate main-actor saturation freeze in long sessions | ✅ Polling chain fix held |
| `5f02f40` | feat(chat): render markdown in Jules agent messages | ✅ Markdown renders correctly |
| `a5151a2` | feat(chat): render markdown tables in agent messages | ✅ Tables render correctly |
| `8bbd2f6` | fix(chat): cache parsed markdown + hoist state-machine resolves | ✅ Parse cache + state hoist held |
| `746e0e6` | test(ui): remove obsolete needs-input heuristic test | (cleanup) |
| `a870b4b` | test: remove obsolete heuristic-based state-machine tests | (cleanup) |
| `be18031` | fix(chat): dismiss keyboard after sending a message | ✅ Keyboard dismisses correctly |
| `a473b90` | fix(chat): eliminate dispatchImmediately freeze with @Observable + view splitting | ⚠️ Did not fully fix freeze #4 |
| `2730287` | feat(chat): unified pixel mascot avatar and quieter status banner | (UI polish, unrelated to freeze) |

**Net architectural improvements (all valid, all keepable):**
- Idempotent SwiftData sync — confirmed correct
- @Observable migration — correct, follows Apple's Swift 5.9+ guidance
- View extraction (LiveChatChrome, ChatMessagesList) — correct, codex-validated
- ContentJSON decode cache — correct
- Markdown Document parse cache — correct
- Polling task chain rewrite — correct
- @ObservationIgnored hygiene — correct

**None of these need to be reverted.** They're all real improvements the codebase should keep. They just don't add up to a freeze fix because the remaining cost is in SwiftUI's layout system itself.

---

## 4. Why More SwiftUI Tweaks Won't Work

This is where I have to be honest about a structural limit, not a bug.

### 4.1 The SwiftUI lazy layout cost model
`LazyVStack` inside `ScrollView` measures every visible cell on every layout invalidation. "Visible" includes a buffer zone above and below the viewport for smooth scroll. With variable-height cells (markdown bubbles), each cell's `sizeThatFits` does real work — walking attributed string layout, line-breaking, image attachment sizing, etc. There is no built-in size-caching the way `UICollectionView`'s `prefetchDataSource` and cell-recycling provide.

Apple's own performance guidance (WWDC23 "Demystify SwiftUI performance" and WWDC25 "Optimize SwiftUI performance with Instruments") explicitly calls out variable-height lazy stacks with heavy cell content as a known cliff. Mitigations exist (`fixedSize`, equatable views, snapshot architecture) but none of them eliminate the underlying per-layout-pass walk — they just reduce its frequency.

### 4.2 The whack-a-mole pattern
| Round | Hot path eliminated | What surfaced next |
|---|---|---|
| 1 (1b2e190) | PollingService task chain | LazyVStack measurement loop |
| 2 (8bbd2f6) | LazyVStack measurement loop | `_UIHostingView.beginTransaction` |
| 3 (a473b90) | Volatile observation in parent body | `_FrameLayout.placement` + SwiftData keypath |
| 4 (would be next) | SwiftData keypath via ActivityRow snapshot | …whatever's underneath |

Each fix is real and the bottleneck moves. But the underlying problem — "SwiftUI walks the LazyVStack subtree on every layout frame and that walk is O(N × cell complexity)" — is not addressed by any of these fixes. We're trimming the leaves without cutting the trunk.

### 4.3 What Apple's own apps do
- **Messages (iMessage)** — UIKit (UITableView)
- **Mail message list** — UIKit
- **Music library** — UIKit
- **Notes list** — UIKit
- **Telegram, Slack, Discord, WhatsApp iOS** — all UIKit for the chat surface

The pattern is consistent: when a list is the *primary surface* of a screen and has variable-height heavy cells under sustained scroll, Apple uses UIKit. SwiftUI is used for the chrome (header, toolbar, settings) but not the list itself. This isn't because SwiftUI is bad — it's because UICollectionView has 15+ years of hard-won optimization for *exactly* this scenario.

### 4.4 What UICollectionView gives us structurally
- **Cell recycling**: a fixed pool of cells is reused as the user scrolls. Layout cost is bounded by viewport size, not by total cell count.
- **Diffable data source (iOS 13+)**: declarative snapshot diffing at the data layer with animations handled by the framework.
- **`UICollectionViewCompositionalLayout`**: declarative section/group/item layout DSL — nearly as ergonomic as SwiftUI for the layout side.
- **`UIContentConfiguration` + `UIHostingConfiguration`** (iOS 16+): cells can host SwiftUI subviews without losing the recycling benefits — so we can keep `PlanCardView`, `CompletionCardView`, etc. as SwiftUI views inside UIKit cells.
- **`prefetchDataSource`** for asynchronous content prefetching.
- **Predictable memory and CPU**: scroll performance is bounded and well-understood.

This isn't a "rewrite the app" pivot. It's a "swap one component" pivot: the message list. Everything else stays SwiftUI.

---

## 5. Detailed UIKit Migration Plan

### 5.1 Goal and scope
**Replace `ChatMessagesList` only.** Keep `ChatHeader`, `LiveChatChrome`, `LiveSessionStatusBanner`, `ChatInputBar`, `MessageSentConfirmationOverlay`, `ErrorAlertHost`, `RefreshToolbarButton`, all the per-activity bubble views (`PlanCardView`, `CompletionCardView`, `ProgressUpdateView`, `CommandCardView`, `FilePillView`, `DiffViewerView`), and the rest of the app exactly as they are.

The new `ChatMessagesList` is a `UIViewControllerRepresentable` that wraps a `UIViewController` hosting a `UICollectionView` with `UICollectionViewDiffableDataSource`. Same input parameters from the parent, same output behavior.

### 5.2 Architecture sketch

```
ChatView (SwiftUI, unchanged)
 ├─ LiveChatChrome (SwiftUI, unchanged)
 ├─ ChatMessagesList — NEW: UIViewControllerRepresentable
 │    └─ ChatMessagesViewController (UIKit)
 │         ├─ UICollectionView
 │         │    ├─ Section: messages
 │         │    │    └─ Items: ActivitySnapshot value-types (id, type, …)
 │         │    └─ Cells configured via UIHostingConfiguration for the heavier
 │         │       activity types (Plan, Completion, Progress) so we keep those
 │         │       SwiftUI views unchanged.
 │         ├─ UIRefreshControl (pull-to-refresh)
 │         └─ ScrollToBottom helper (collectionView.scrollToItem)
 └─ ChatInputBar (SwiftUI, unchanged)
```

**Data flow:**
1. `ChatMessagesList` receives `session: SessionEntity` and `viewModel: ChatViewModel` from the parent.
2. It owns a `@Query` that produces `[ActivityEntity]` (same as today).
3. On every `@Query` update, it converts to `[ActivitySnapshot]` (a value-type wrapper with the few fields the cells need: id, type, createdAt, contentJSON ref, sendStatus, etc.).
4. It applies the snapshot to the data source via `dataSource.apply(snapshot, animatingDifferences: true)`.
5. The data source diffs against the previous snapshot and animates inserts/deletes/moves.
6. Each cell is dequeued and configured from its `ActivitySnapshot`. For heavy cells (PlanCardView, CompletionCardView), the cell uses `UIHostingConfiguration` to embed the existing SwiftUI view.
7. Polling continues unchanged. The polling service writes to SwiftData, `@Query` updates, snapshot diff, animated update.

### 5.3 Cell strategy by activity type

| Activity type | Cell strategy | Notes |
|---|---|---|
| `userMessaged` | Native UIKit cell with `UILabel` (NSAttributedString) | Right-aligned bubble, simple text |
| `agentMessaged` | Native UIKit cell with `UITextView` (NSAttributedString) | Markdown via existing `InlineAttributedStringBuilder` extended for blocks |
| `planGenerated` | `UIHostingConfiguration` wrapping `PlanCardView` | Reuse existing SwiftUI |
| `progressUpdated` | `UIHostingConfiguration` wrapping `ProgressUpdateView` | Reuse existing SwiftUI |
| `sessionCompleted` | `UIHostingConfiguration` wrapping `CompletionCardView` | Reuse existing SwiftUI |
| `sessionFailed` | Native UIKit cell with icon + label | Lightweight |
| `planApproved` | Native UIKit cell with icon + label | Lightweight |

The split is **render-cost driven**: heavy SwiftUI views (Plan, Completion, Progress) stay as SwiftUI inside `UIHostingConfiguration` because rewriting them in UIKit gains nothing — they're leaf views, not list cells under sustained scroll. Their cost was acceptable; the problem was always the *outer* LazyVStack walking them, not their internal SwiftUI rendering.

### 5.4 Markdown rendering
The existing `MarkdownText` SwiftUI view contains the work that matters: `InlineAttributedStringBuilder` already produces an `AttributedString` from a swift-markdown AST node. For UIKit cells, I'll extend this to produce a full `NSAttributedString` for the entire markdown document (not just inline runs):

- **Paragraphs**: NSAttributedString with paragraph spacing
- **Headings**: NSAttributedString with bold + size
- **Inline code**: monospaced font + background color
- **Code blocks**: separate NSAttributedString span with monospaced font, background, padding via `NSParagraphStyle`
- **Lists**: bullet/number prefixes via paragraph style indents
- **Blockquotes**: left-indent paragraph style + secondary color
- **Tables**: tricky in pure NSAttributedString — fallback to a `UIView` subhierarchy embedded via `NSTextAttachment`, OR (cleaner) use `UIHostingConfiguration` to embed a SwiftUI table view from the existing `TableView` in `MarkdownText.swift` for table rows specifically. Tables are rare enough that the hybrid is acceptable.
- **Links**: NSAttributedString with `.link` attribute, `UITextView.delegate` handles taps.

The markdown renderer becomes a `MarkdownNSAttributedString.build(from: String) -> NSAttributedString` function. The existing SwiftUI `MarkdownText` view stays for any non-cell uses (currently none in the chat path after this migration).

### 5.5 SwiftUI ↔ UIKit bridge

```swift
struct ChatMessagesList: UIViewControllerRepresentable {
    let session: SessionEntity
    @Bindable var viewModel: ChatViewModel

    func makeUIViewController(context: Context) -> ChatMessagesViewController {
        ChatMessagesViewController(session: session, viewModel: viewModel)
    }

    func updateUIViewController(_ uiViewController: ChatMessagesViewController, context: Context) {
        // The view controller observes its own @Query through a wrapper;
        // this update method is mostly a no-op except for parameter changes.
    }
}
```

The `ChatMessagesViewController` itself uses an internal `ActivityFetcher` actor that owns the `FetchDescriptor` and notifies the view controller of updates. We don't use `@Query` inside the view controller (it's a UIKit class) — instead we hook into SwiftData's `NSManagedObjectContext.didSave` notification or use a `FetchedResultsController`-style wrapper.

**Or a simpler bridge:** the `ChatMessagesList` `UIViewControllerRepresentable` keeps `@Query` at the SwiftUI level (the representable IS a SwiftUI view) and passes the activity array to the view controller via the `updateUIViewController` callback. Each call computes a snapshot diff and applies. SwiftUI's `updateUIViewController` is called only when the inputs change, which under idempotent sync happens only on real activity updates.

**I'll use the second approach** — it's strictly simpler and reuses the @Query infrastructure we already have.

### 5.6 Scrolling behavior
- **Pull-to-refresh**: `UIRefreshControl` attached to the collection view; on `valueChanged`, calls `viewModel.manualRefresh()`.
- **Scroll-to-bottom on new message**: after `dataSource.apply(snapshot)`, if the count grew, `collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: true)`.
- **Initial appearance**: scroll to bottom non-animated.
- **Background polling integration**: unchanged. Polling writes to SwiftData, `@Query` updates the SwiftUI side, `updateUIViewController` is called, snapshot diff, animated update.

### 5.7 Empty/loading states
- **Loading**: when `viewModel.isLoading && activities.isEmpty`, show a centered `ProgressView` (UIKit `UIActivityIndicatorView` or a SwiftUI overlay outside the view controller).
- **Empty**: when `!isLoading && activities.isEmpty`, show the `EmptyActivitiesView` (existing SwiftUI) as an overlay above the collection view.

These can stay in the parent SwiftUI `ChatView` since they don't need cell recycling.

### 5.8 Implementation phases

| Phase | Description | Est. time |
|---|---|---|
| 1 | Bootstrap `ChatMessagesViewController` with empty `UICollectionView` + `UIViewControllerRepresentable` wrapper. Verify it appears in the chat view. | 1h |
| 2 | Define `ActivitySnapshot` value-type, `Section` enum, `UICollectionViewDiffableDataSource` setup. | 1h |
| 3 | Native UIKit cells for `userMessaged`, `agentMessaged`, `sessionFailed`, `planApproved`. UILabel-based with NSAttributedString. | 1.5h |
| 4 | Extend `InlineAttributedStringBuilder` → `MarkdownNSAttributedString.build(from:)` for all block types except tables. | 2h |
| 5 | `UIHostingConfiguration`-based cells for `planGenerated`, `sessionCompleted`, `progressUpdated`. Reuse existing SwiftUI views. | 1h |
| 6 | Markdown table rendering — embed existing SwiftUI `TableView` via `UIHostingConfiguration` inside the agent message cell when a table is present. | 1.5h |
| 7 | Pull-to-refresh, scroll-to-bottom, animations, transitions. | 1h |
| 8 | Empty/loading state overlays in the parent SwiftUI view. | 30m |
| 9 | Testing — run the existing freeze repro pattern (multi-minute scroll + polling + sends). Confirm via process sample that the LazyVStack/UpdateStack hot paths are gone. | 1.5h |

**Total: ~11 hours.** I previously estimated 6–8h but I'm being more honest about the markdown table edge case and testing. Could be faster if table rendering is skipped initially (markdown without tables in cells, tables fall back to a less-pretty rendering).

### 5.9 Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `UIHostingConfiguration` has subtle render bugs with `@Observable` view models | Medium | Test the Plan/Completion cards specifically; if buggy, fall back to a simple "data passed through, no observation" subview. |
| Markdown table rendering in NSAttributedString is rough | High | Use the SwiftUI hybrid (UIHostingConfiguration for table rows) — accepts the cost of N tables × hosting overhead, which is fine because tables are rare. |
| Cell sizing under variable-content markdown blocks is hard with self-sizing collection view layouts | Medium | Use `UICollectionViewCompositionalLayout` with `.estimated(...)` heights and let the layout settle; rely on cell `preferredLayoutAttributesFitting(_:)` for self-sizing. |
| Animation glitches when SwiftData updates fire mid-scroll | Medium | Use `animatingDifferences: false` during sustained scroll (detect via `scrollViewDidScroll` / `decelerationDidEnd`). |
| Optimistic-message reconciliation logic in `ChatViewModel` may need adjustment | Low | The reconciliation lives in the view model and writes to SwiftData; the UIKit list just reflects whatever's in the data store. Should "just work." |
| Bridging `viewModel.isSending` for the input bar's disabled state | Low | `ChatInputBar` is unchanged SwiftUI; not affected by this migration. |
| Lost feature: SwiftUI transitions on cell appear (`.scale.combined(with: .opacity)`) | Low | UICollectionView has its own appear/disappear animations. They look fine. |

### 5.10 Feature parity checklist

The new chat message list MUST preserve every behavior currently in `ChatMessagesList`:

- [ ] Renders all activity types (user, agent, plan, progress, completed, failed, plan-approved, working-card)
- [ ] Renders markdown in agent messages (paragraphs, headings, lists, bold, italic, inline code, code blocks, blockquotes, links)
- [ ] Renders markdown TABLES in agent messages
- [ ] Plan card has working Approve/Revise buttons (when canRespondToPlan)
- [ ] Plan card respects `canRespondToPlan` flag (historical plan cards stay inert)
- [ ] Completion card shows diff stats, file pills, PR card if PR was created
- [ ] Progress update shows bash command cards if present
- [ ] User message bubble shows send status icon (pending/sent/failed)
- [ ] Optimistic message bubbles render before server reconciliation
- [ ] Pull-to-refresh works
- [ ] Scroll-to-bottom on new activity insert
- [ ] Empty state shown when activities is empty
- [ ] Loading state shown when initial fetch is in progress
- [ ] "Made with ❤️ by indrasvat" footer at the bottom
- [ ] Typing indicator shown when state is `.running` / `.inProgress` / `.queued`
- [ ] Existing accessibility identifiers (`chat.scroll`, `chat.refresh`, `chat.input`, `chat.send`, `plan.approve`, `plan.revise`, `chat.working-card`) preserved
- [ ] Existing UI tests pass (or are updated to match the UIKit equivalents)
- [ ] Background → foreground transition works
- [ ] Session state transitions (queued → running → completed) animate cleanly
- [ ] Light + dark mode rendering correct
- [ ] Repoless and repo-bound sessions both work

### 5.11 What we delete after the migration
Once the UIKit list is in place and verified:

- The current SwiftUI `ChatMessagesList` definition (~150 lines)
- Some of the observer wrapper views become unnecessary if `ChatMessagesViewController` reads them directly through the bindable `viewModel`. To be evaluated.
- The `MarkdownText` SwiftUI view stays for non-cell uses (e.g. preview, if any) but is no longer on the chat hot path.

Everything else from the freeze fix (idempotent sync, @Observable, NSCache, view extraction, observer wrappers, teardown, isConfigured guard) stays. They were correct fixes; they just weren't sufficient by themselves.

---

## 6. Open Questions for the Council

These are the things I want codex and gemini to weigh in on before I start the migration. Both because I want a sanity check on the plan, and because they may catch failure modes I'm missing.

1. **Is the UIKit pivot the right call given the data?** Or is there one more SwiftUI trick I haven't tried (e.g., precomputed cell heights stored on `ActivityEntity`, eager VStack with capped activity count, `UICollectionView`-backed `List`)? Specifically — would using the new SwiftUI `List` with `.listRowSeparator(.hidden)` and per-row `.id()` give us cell recycling without going to UIKit?

2. **`UICollectionView` vs `UITableView` for chat?** Diffable data sources are in both. UICollectionView has `UICollectionViewCompositionalLayout` which is more flexible. UITableView has slightly simpler self-sizing for variable-height content. Which is the better choice in 2026?

3. **`UIHostingConfiguration` safety inside cells.** Is it safe to embed a SwiftUI view that observes `@Observable` `ChatViewModel` inside a recycled `UICollectionView` cell? I've heard reports of cells losing observation when recycled. Is there a known correct pattern, or do we need to make the embedded views fully stateless and pass data via parameters?

4. **Markdown tables in NSAttributedString.** Is there a clean approach? My plan is the SwiftUI hybrid (embed `TableView` via `UIHostingConfiguration` for cells that contain tables). Is there a better idiom?

5. **Self-sizing `UICollectionViewCompositionalLayout` with variable-height markdown content.** What's the modern pattern (2026) for getting cells to size themselves correctly when their content is a multi-line attributed string with embedded SwiftUI subviews? I'm worried about layout-pass instability.

6. **Bridging `@Query` results into a UIViewControllerRepresentable.** The plan is to keep `@Query` in the SwiftUI representable and pass the array down through `updateUIViewController`. Is that idiomatic, or is there a better way (e.g., `FetchedResultsController` analog, `NSManagedObjectContext.didSave` hook)?

7. **Are there any architectural moves that would let us SAVE the SwiftUI version instead of pivoting?** Specifically — would moving `ActivityEntity` from a SwiftData `@Model` reference type to a value-type `ActivitySnapshot` (computed once per sync, stored in the view model as `[ActivitySnapshot]`, fed to the SwiftUI `LazyVStack` ForEach) eliminate the SwiftData keypath getter cost AND let SwiftUI's view diffing short-circuit re-renders? In other words: if the freeze cause is "SwiftUI keeps walking SwiftData entities through ObservationRegistrar," does swapping the entities for value types make the SwiftUI version viable?

8. **Time estimate honesty check.** I said 11 hours. Is that realistic, or am I underestimating?

Be brutal. I want to know if the pivot is the wrong call before I commit to 11 hours of work.

---

## 7. High-level options for the user

Before any code is written, the user needs to choose between three concrete paths:

**Option A — UIKit pivot for the message list (recommended).**
Cost: ~11h. Eliminates the freeze category structurally. Loses no features (uses `UIHostingConfiguration` to keep the heavy SwiftUI cells). Lands on the same architecture Apple's own apps use for chat surfaces.

**Option B — One more SwiftUI attempt: value-type snapshots.**
Cost: ~3-4h. Convert `ChatMessagesList`'s ForEach to iterate over `[ActivitySnapshot]` (value types) instead of `[ActivityEntity]` (SwiftData @Model). The view model owns the snapshot computation and only republishes on actual data change. Eliminates the SwiftData keypath getter cost from the layout-pass hot path. **High uncertainty whether it's enough** — the deeper LazyVStack frame placement work is independent of SwiftData and would likely still dominate. Risk: one more iteration, one more freeze report, more wasted time.

**Option C — Status quo + accept the freeze.**
Cost: 0h. Ship as-is, document the known limitation, focus on other features. Not really an option since the user has said the app is unusable in this state.

The recommendation is **Option A**, but I want the council to validate it before committing.

---

## 8. Appendix — Sample artifacts

All freeze samples and stress test results are in `/tmp/freeze-monitor-*/` and `/tmp/jools-sample-*.txt` on the dev machine. They include the call graphs that informed every diagnosis in this document.

---

## 9. dootsabha Council Review (codex + gemini, 2026-04-07)

### 9.1 Codex (gpt-5.3-codex)

**Verdict**

The pivot is directionally right, but your current plan is too expensive in the wrong places.

The structural problem is real: the live chat surface is still a SwiftUI `ScrollView` + `LazyVStack` over SwiftData `@Model` rows in [`ChatView.swift`](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/ChatView.swift#L168), with identity resolved through `ActivityEntity.id` and row content pulling computed accessors off a reference type in [`Entities.swift`](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Core/Persistence/Entities.swift#L168). That is exactly the kind of surface where SwiftUI can keep getting “better but still not done.” Your markdown renderer is also still a view tree of nested stacks and `ForEach` in [`MarkdownText.swift`](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/Views/MarkdownText.swift#L47), which is fine as a leaf, but expensive when the outer list keeps relaying out.

What I would not do is rewrite markdown into `NSAttributedString` now. That is the highest-risk part of the plan and it solves the least important problem.

**Answers**

1. The UIKit pivot is justified. The only SwiftUI retry I’d consider is not “snapshots + keep `LazyVStack`”; it is “snapshots + `List`.” Apple’s guidance is that `List`/`Table` gather IDs up front and create rows on demand, while `LazyVStack` is still just a lazy layout container, not a recycled list surface. If you want one last bounded experiment, do that. Otherwise pivot.

2. Use `UITableView`, not `UICollectionView`, unless you know you need multi-section compositional behavior soon. This is a single-column chat transcript with self-sizing variable-height cells. `UITableViewDiffableDataSource` plus `automaticDimension` is lower risk and faster to land.

3. `UIHostingConfiguration` is safe in cells if the hosted SwiftUI content is stateless. Do not let cell content observe `@Observable`, `@Query`, `SessionEntity`, or `ActivityEntity` directly. Pass immutable snapshots plus closures. If you host `PlanCardView(activity: ActivityEntity, ...)` as-is, you reintroduce observation and SwiftData reads into recycled cells.

4. Do not build markdown tables in `NSAttributedString`. That path is a trap. Keep agent-message rows as hosted SwiftUI using your existing `MarkdownText`, including tables. The whole point of the pivot is to replace the outer container, not to rewrite the renderer.

5. For self-sizing, `UITableView.automaticDimension` is the modern low-drama answer here. If you insist on collection view, use list configuration plus estimated heights, not a bespoke compositional layout from scratch.

6. Bridging `@Query` through the representable is fine, but pass `[ActivitySnapshot]`, not `[ActivityEntity]`, into UIKit. Keep SwiftData at the bridge boundary. The controller should know nothing about `@Model` types.

7. A value-type snapshot can save SwiftUI only if you also stop using `ScrollView + LazyVStack`. Snapshots alone will remove the SwiftData keypath cost, but they will not eliminate the repeated outer layout work you’re still seeing. `snapshot + List` is a plausible last SwiftUI spike. `snapshot + LazyVStack` is low-confidence and probably another dead end.

8. `11h` is high if you stop rewriting markdown and choose `UITableView`. My estimate:
- `4-6h` for `UITableViewDiffableDataSource` + snapshot bridge + hosted SwiftUI cells
- `1-2h` for parity cleanup and scroll/refresh behavior
- `1-2h` for repro verification

So call it `6-8h` realistic, `9h` with test fallout. `11h` only makes sense if you insist on native UIKit markdown rendering.

**Recommended path**

Option A, but tighten it:

1. Build `ActivitySnapshot` and `SessionSnapshot` value types at the SwiftUI boundary.
2. Replace [`ChatMessagesList`](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/ChatView.swift#L168) with `UIViewControllerRepresentable`.
3. Use `UITableViewDiffableDataSource`.
4. Use `UIHostingConfiguration` for all non-trivial rows, including agent markdown rows.
5. Make hosted row views snapshot-driven, not entity-driven.
6. Keep pull-to-refresh, footer, typing row, and plan actions as explicit snapshot items.

If you want one final SwiftUI spike before committing, make it a hard 2-3 hour experiment: swap to `List` backed by `[ActivitySnapshot]`. If it is not clearly stable under the same repro on the same day, stop and do UIKit.

Sources: Apple WWDC23 on SwiftUI dependencies, IDs, and on-demand `List` row creation: https://developer.apple.com/videos/play/wwdc2023/10160/ . Secondary practical guidance on using `UIHostingConfiguration` for performance-sensitive list surfaces: https://swiftwithmajid.com/2025/03/04/swiftui-performance-how-to-use-uikit/ .

### 9.2 Gemini (gemini-3-pro)

I have completed a thorough review of your analysis and the current state of the Jools codebase. Your forensic work on the 1Hz polling vs. `LazyVStack` measurement loop confirms that you've hit the limit of SwiftUI’s "reactive layout" model for this specific use case.

Here is the "brutal" feedback and sanity check you requested:

### 1. Is the UIKit pivot the right call?
**Yes.** You have already exhausted the standard SwiftUI optimization playbook (view splitting, observation pruning, `NSCache` for ASTs, idempotent sync). The fact that the bottleneck moved from `LazyVStackLayout.sizeThatFits` to `_ZStackLayout.placeSubviews` confirms that the framework itself is the bottleneck. In a chat app, the message list is the "engine," and `UICollectionView` is a significantly more powerful engine for high-frequency, variable-height updates.

### 2. `UICollectionView` vs `UITableView`?
**`UICollectionView` + `CompositionalLayout` is the correct 2026 choice.** `UITableView`'s self-sizing can be more temperamental with `UIHostingConfiguration`. `UICollectionViewCompositionalLayout` with `.estimated(100)` and `UICollectionViewDiffableDataSource` provides the most stable foundation for mixing native `NSAttributedString` cells with "heavy" SwiftUI cells.

### 3. `UIHostingConfiguration` safety inside cells
**Safety: High, with a caveat.** The risk isn't that `UIHostingConfiguration` is buggy, but that the SwiftUI views inside the cells might still hold onto expensive observation registrations.
*   **Refinement:** Do **not** pass the `ChatViewModel` or `ActivityEntity` directly into the SwiftUI views inside the cells. Map them to a **stateless value-type snapshot** (`ActivitySnapshot`) first. This ensures that when a cell is recycled, it isn't still "listening" to the polling service for an activity that is now off-screen.

### 4. Markdown tables in NSAttributedString
**Pragmatism Wins.** Your plan to use the SwiftUI hybrid (embedding the existing `TableView` via `UIHostingConfiguration`) is the right call. `NSAttributedString` was never designed for tables, and any UIKit-native table implementation will take longer to build than the rest of the migration combined. Since tables are rare, the "hosting overhead" will not trigger the freeze you're seeing today.

### 5. Self-sizing stability
**Risk: Medium.** The jitter usually occurs when a cell's size changes *after* it has been dequeued. 
*   **Mitigation:** Ensure the `MarkdownNSAttributedString.build(from:)` call happens **before** the snapshot is applied (e.g., in a background pre-processing step) so the cell has its final content immediately upon configuration.

### 6. Bridging `@Query` results
**Recommendation:** The `updateUIViewController` bridge is fine for now, but as the session grows, computing a 100-item snapshot on every poll tick will cost ~2-5ms. 
*   **Pro Tip:** Use `dataSource.applySnapshotUsingReloadData` only for the initial load. For polling updates, use the standard `apply` to get the high-performance linear diffing.

### 7. Can we save the SwiftUI version (Option B)?
**No.** Even if you eliminate the SwiftData keypath cost, the `LazyVStack` still has to walk its children to calculate the scrollable content size. That walk is the "trunk" of the problem. UIKit solves this by decoupling the "data count" from the "view count."

### 8. Time estimate honesty check
**11 hours is a "Senior Dev" estimate.** It assumes no major issues with keyboard-avoidance logic or scroll-to-bottom race conditions. 
*   **Realistic adjustment:** I’d budget **15 hours**. The extra 4 hours will be spent on the "last 10%": ensuring the scroll-to-bottom feels as smooth as the original and handling the `UITextView` delegate interactions for markdown links.

---

### **Strategic Recommendation: Proceed with Option A**

This is the right move for Jools. You are swapping a component that is struggling with its fundamental cost model for one that was purpose-built for it.

**Next Step:** I recommend starting with **Phase 1 & 2** immediately: build the `ChatMessagesViewController` scaffold and the `ActivitySnapshot` mapping. This will prove the bridge works before you invest in the markdown rendering logic. 

**Do you want me to generate the `ActivitySnapshot` definition and the `ChatMessagesViewController` scaffold now?**

### 9.3 Synthesis (council convergence)

**Unified Answer**

The strong consensus is that your diagnosis is sound: the freeze is no longer primarily a SwiftData sync bug, it is a list-surface cost problem. The current chat transcript is still a SwiftUI `ScrollView` + `LazyVStack` over live SwiftData-backed entities in [ChatView.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/ChatView.swift#L168) and [Entities.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Core/Persistence/Entities.swift#L168), and agent markdown is still rendered as a fairly heavy SwiftUI tree in [MarkdownText.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/Views/MarkdownText.swift#L47). That combination is the wrong cost model for a live-updating chat surface with variable-height rows.

The synthesis, though, is more precise than either single review:

1. A UIKit pivot is justified, but not because SwiftUI has been mathematically disproven in all forms. What has likely hit its limit is `LazyVStack` on this surface. There is still one bounded SwiftUI experiment worth considering: `ActivitySnapshot` + `List`, because the current implementation still contains volatile `viewModel` reads inside the list subtree and still iterates SwiftData entities directly in [ChatView.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/ChatView.swift#L211), [ChatView.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/ChatView.swift#L243), and [ChatView.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/ChatView.swift#L252). So “SwiftUI is exhausted” is too absolute; “`LazyVStack` is exhausted” is the evidence-backed statement.

2. If you do pivot, the lowest-risk implementation is `UITableView`, not `UICollectionView`. Gemini’s `UICollectionView` recommendation is reasonable in general, but the repo evidence does not justify it over `UITableView` for this specific single-column, self-sizing chat transcript. `UITableViewDiffableDataSource` + `automaticDimension` is the tighter path unless you already know you need more complex section/layout behavior.

3. `UIHostingConfiguration` is appropriate, but only if cells are snapshot-driven. Both reviews converge on the important guardrail: do not pass `ActivityEntity`, `SessionEntity`, `@Query` results, or observable view models into hosted cells. Build value-type snapshots at the boundary and keep UIKit ignorant of SwiftData.

4. Do not rewrite markdown into `NSAttributedString` right now. That part of the original migration plan is the least justified and highest risk. It also prompted speculative advice about a nonexistent pipeline like `MarkdownNSAttributedString.build(from:)`, which is not reflected in the current code. The practical move is to keep agent rows as hosted SwiftUI using existing `MarkdownText`, especially for rare table cases already handled in [MarkdownText.swift](/Users/indrasvat/code/github.com/indrasvat-jools/Jools/Features/Chat/Views/MarkdownText.swift#L287).

5. The real architectural win is not “UIKit everywhere.” It is “value snapshots + recycled outer list surface.” That is the core change. Everything else is secondary.

**Recommended Path**

Proceed with a tightened version of Option A:

1. Define `ActivitySnapshot` and `SessionSnapshot` value types at the SwiftUI boundary.
2. Replace the current message list surface with a `UIViewControllerRepresentable`.
3. Implement the UIKit list as `UITableViewDiffableDataSource`.
4. Use `UIHostingConfiguration` for complex rows, including markdown rows and table-containing agent responses.
5. Ensure every hosted row is stateless and snapshot-based.
6. Treat typing indicator, footer, refresh state, and plan actions as explicit snapshot items, not live model reads inside cells.

If you want one final SwiftUI spike before committing, make it a hard-boxed 2-3 hour experiment only: swap the transcript to `List` backed by `[ActivitySnapshot]`. If that does not clearly eliminate the freeze under the same repro, stop and do UIKit.

**Time Estimate**

The best grounded estimate is between the two reviews:

- `6-8h` is plausible if you choose `UITableView` and do not rewrite markdown.
- `11h` is still a defensible planning number if you include parity cleanup, scroll behavior, and test fallout.
- `15h` reads too speculative for the evidence currently on the table.

So the honest planning number is: budget `8-11h`, with risk concentrated in scroll-to-bottom behavior, keyboard interactions, and self-sizing parity.

**Bottom Line**

The migration direction is right. The plan should be narrowed, not expanded:

- pivot the outer container,
- snapshot the data,
- keep markdown rendering mostly as-is,
- prefer `UITableView`,
- and only spend more time on SwiftUI if `snapshot + List` gets a very short, explicit last chance.

---

## 10. Jules Web UI — Forensic Analysis (via Chrome DevTools MCP, 2026-04-07)

Before committing to any pivot, I inspected the official Jules web UI
under the same stress patterns that freeze the iOS app. Goal: learn
what architecture Google's own Jules client uses to solve the same
problem. Tests were run against a live authenticated session on
`jules.google.com` via the Chrome DevTools MCP.

### 10.1 Framework identification

| Property | Value |
|---|---|
| Framework | **Angular** (Angular Material, `mat-icon`) |
| Component model | Native Angular custom elements (`swebot-*` tags) |
| Virtualization | **NONE** (`cdk-virtual-scroll-viewport` not present) |
| CSS containment | **NONE** (`contain: none`, `content-visibility: visible`) |
| Shadow DOM | Not used |
| Streaming transport | HTTP polling via Google's `batchexecute` RPC (NOT WebSocket/SSE) |
| Markdown rendering | Flat HTML output: `<div class="markdown typography">` containing plain `<p>`, `<strong>`, `<ol>`, `<li>`, `<code>` — ~3-4 HTML elements per markdown block |

### 10.2 Custom element surface

The chat surface is composed of discrete Angular components, mirroring
almost exactly the SwiftUI view hierarchy in Jools:

```
swebot-chat
  .chat-content (scroll container)
    swebot-user-chat-bubble
    swebot-agent-chat-bubble
      swebot-markdown-viewer × N    ← content rendering unit
    swebot-plan
      swebot-expansion-panel-row × N
    swebot-progress-update-card
    swebot-critic-card
    swebot-submission-card
    swebot-input-box (bottom)
```

### 10.3 DOM complexity is dramatically lower than SwiftUI

For a session with 14 markdown viewers (the first comprehensive Swift 6
response with a table, bold runs, lists, code blocks):

| Metric | Value |
|---|---|
| Total `<*>` elements across all 14 markdown viewers | **46** |
| Average HTML elements per markdown viewer | **3.3** |
| Tag mix | `div:14, p:15, strong:7, ol:1, li:5, code:4` |
| Total chat DOM nodes | 217 |
| JS heap used | 75 MB / 96 MB total |

For comparison, the SwiftUI `MarkdownText` view for a single paragraph
with bold text creates:

```
VStack
  ForEach
    MarkdownBlockView
      ParagraphView
        Text(AttributedString built from InlineAttributedStringBuilder)
```

That's at least 5 nested SwiftUI views per paragraph, plus Text attribute
runs. A single agent bubble in Jules iOS with 14 markdown blocks could
easily produce **80-100 nested SwiftUI views**, all of which SwiftUI has
to evaluate on every re-render.

**Angular outputs flat HTML. SwiftUI outputs deeply-nested view structs.**

### 10.4 Streaming / polling — NOT via WebSocket

Jules Web uses Google's `batchexecute` HTTP RPC protocol — the same
pattern Gmail, Docs, and Drive use. Each RPC call is a discrete POST
to `/_/Swebot/data/batchexecute?rpcids=...&source-path=/session/...`.

| RPC ID | Calls | Total bytes | Avg duration |
|---|---|---|---|
| `p1Takd` | 54 | 985 KB | 518 ms |
| `n74qPd` | 101 | 202 KB | 453 ms |
| `cFjlx` | 24 | 296 KB | 213 ms |
| (13 other one-shot RPCs) | 1 each | — | varies |

**Key observations:**

1. **Jules web polls like we do.** There is no magical WebSocket or
   Server-Sent Events pipeline. It's plain HTTP RPC, exactly the same
   model our iOS app uses.
2. **Polling STOPS when the session is idle.** In a 5-second window
   with the session in "awaiting user input" state, **zero**
   `batchexecute` calls fired. This matches our iOS polling service's
   intent but suggests Jules's transport is more aggressive about
   stopping.
3. **Polling does not drive UI re-renders unless the data actually
   changes.** Angular's zone-based change detection only runs when
   something mutates the state.

### 10.5 Performance under the same stress patterns that freeze iOS

**Test A — Static session, 10 rounds of top-to-bottom scroll (3.5s, 100 scroll events):**

```
CLS: 0.00
Performance insights flagged: ThirdParties (GTM/analytics only, irrelevant)
App-level console errors/warnings: 0
```

**Test B — Fresh session with streaming follow-up message, 20s aggressive scroll (498 events, ~25/sec):**

```
DOM mutations observed during scroll: 0
Max main thread stall between scroll steps: 124 ms (one tiny blip)
Median stall: 62 ms (expected baseline of setTimeout)
CLS: 0.00
```

**Test C — Plan-approved session, 30s aggressive scroll during content streaming (988 events, ~33/sec):**

```
DOM nodes before: 136
DOM nodes after: 217 (81 nodes added during scroll from streaming)
Scroll height before: 1483 px
Scroll height after: 1944 px (460 px of new content added)
Markdown viewers before: 7
Markdown viewers after: 14
Max main thread stall: 64 ms
Median stall: 62 ms
CLS: 0.01 (one small layout shift from new content)
App-level warnings: 0
```

### 10.6 Direct iOS vs Web comparison under identical stress

| Metric | Jools iOS (v2 fixes) | Jules Web (Angular) |
|---|---|---|
| Stress duration | 5 s sample | 30 s sample |
| Scroll events | manual | 988 |
| Active streaming during test | yes | yes |
| Main thread busy % | **98.6 % (frozen)** | **<3 %** (imperceptible) |
| Max main thread stall | **5000+ ms** (frozen) | **64 ms** (~4 frames) |
| Layout shift (CLS) | N/A | **0.01** |
| UI responsive? | **NO — frozen** | **YES — fully responsive** |

### 10.7 Why Angular wins here (and the counter-intuitive lesson)

Angular has a REPUTATION for being heavy. In most benchmarks, React,
Vue, and especially SolidJS or Svelte outperform it. And yet Angular
is **the right tool** for this surface. Here's why:

1. **Zone-based change detection is COARSER than `@Observable`
   per-property tracking, and in this case coarser is better.**
   Angular runs change detection in discrete phases tied to "zone"
   boundaries (an HTTP response completes, a timer ticks, a click
   handler returns). Ten rapid state updates in the same zone = ONE
   change detection pass. Ten rapid `@Observable` property mutations
   = ten body re-evaluations. Counter-intuitively, `@Observable`'s
   fine-grained tracking is a footgun for polling-driven UIs.

2. **Browser layout caching is mature.** Chrome's Blink engine caches
   layout of stable subtrees and only invalidates the dirty parts.
   CSS containment helps but is not required — the engine figures out
   reflow boundaries on its own. SwiftUI's `LazyVStack` layout system
   has no such caching: it walks children on every invalidation and
   calls `sizeThatFits` on each.

3. **Flat HTML DOM is cheap.** Each markdown viewer is ~3 HTML
   elements. A SwiftUI markdown bubble is ~50+ views. Even before any
   layout cost, the sheer **view count** that SwiftUI has to diff is
   an order of magnitude higher.

4. **No eager view tree evaluation.** Browser engines only run
   JavaScript when the call stack asks them to. They don't walk the
   DOM on every frame. SwiftUI's render loop walks the view tree
   every time a state observation fires.

### 10.8 What this means for the iOS pivot

Revalidating the council recommendation with this data:

**The UIKit pivot is the right call, and the web data makes it stronger.**
UIKit's `UITableView` + `UITableViewDiffableDataSource` behaves much
more like the browser than like SwiftUI — incremental layout, cached
cell sizes, explicit invalidation, no eager walk. The browser's DOM
+ Blink is the gold standard for "N-variable-height-cells-under-scroll";
`UITableView` is the iOS equivalent. `SwiftUI LazyVStack` is not.

**But the web data ALSO justifies trying the Option B SwiftUI `List`
spike first**, because:

1. `List` in SwiftUI is backed by `UICollectionView` under the hood.
   It uses the same native recycling the web's browser layer uses.
2. If we pair `List` with `[ActivitySnapshot]` value types (per codex's
   advice), we eliminate the SwiftData keypath getter cost too.
3. The spike is 2-3 hours; if it holds, we're done; if not, we pivot
   to `UITableView` with complete certainty.

**Additional learning for the UIKit pivot architecture, informed by
Jules web:**

1. **Render markdown to flat HTML-equivalent.** In UIKit-land, that
   means `NSAttributedString` with paragraph style runs for entire
   documents, not one-SwiftUI-view-per-inline-element. The existing
   `InlineAttributedStringBuilder` already produces correct
   `AttributedString`; extending it to cover block-level constructs is
   less work than I budgeted.

2. **For `UIHostingConfiguration`-hosted SwiftUI cells, keep the
   SwiftUI view tree shallow.** The "one `Text(AttributedString)`
   per bubble" pattern matches what Angular does with a single
   `<div class="markdown">`.

3. **Explicit invalidation, not implicit observation.** In the UIKit
   list, we decide when to call `dataSource.apply(snapshot:)`.
   Nothing in the cell observes `ChatViewModel` or `SessionEntity`
   directly. This mirrors Angular's zone model — updates happen at
   clearly-defined moments, not continuously.

### 10.9 The (slightly embarrassing) summary

The single biggest architectural difference between Jools iOS and
Jules web isn't the framework choice. It's the **view-tree depth
per rendered unit of content**. Jules web produces ~3 HTML elements
per markdown block. SwiftUI Jools produces ~50 views per markdown
block. That ratio is the root cause. The LazyVStack measurement
loop, the @Observable invalidation cascade, the SwiftData keypath
getter — those are all symptoms of asking SwiftUI to evaluate and
lay out a 15×-deeper view tree on every frame.

The fix, whether we ship it as SwiftUI `List` + `ActivitySnapshot`
or as `UITableView` + `UIHostingConfiguration`, is the same in
principle: **flatten the content, batch the invalidation, let the
platform's native recycling do its job**. Jules web does this via
Angular zones + flat HTML + browser layout caching. Jools iOS needs
to do it via `UITableView` cells + `NSAttributedString` + explicit
snapshot apply.

