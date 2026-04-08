# Option B — SwiftUI `List` + `ActivitySnapshot` + Flattened Markdown

**Timebox:** 3 hours (hard stop — pivot to Option A / UIKit if not holding under stress test by then)
**Goal:** Eliminate the chat-surface freeze without leaving SwiftUI, by addressing the root cause (view-tree depth + observation granularity) rather than the symptoms.
**Derived from:** Council review (codex + gemini, council pass #3) + Jules web UI forensic analysis (see `Chat_Freeze_Analysis_and_UIKit_Migration_Plan.md` section 10).

---

## 1. The three principles

1. **Snapshot, don't observe.** The chat list iterates value-type `ActivitySnapshot`s, never `ActivityEntity` references. Zero SwiftData observation cost in the layout-pass hot path. *(Council recommendation, codex + gemini convergence.)*
2. **Recycle, don't walk.** SwiftUI `List` (not `LazyVStack`) — backed by `UICollectionView` under the hood with native cell recycling. *(Council recommendation, "one last SwiftUI spike worth trying.")*
3. **Flatten, don't nest.** Each agent message bubble renders as **one** `Text(AttributedString)` covering most block-level content, with separate subviews only for fenced code blocks and markdown tables. View tree depth goes from ~50 nested views per markdown block down to 1–3. *(New — derived from Jules web forensic analysis: Angular outputs ~3 HTML elements per markdown block; SwiftUI currently outputs ~50.)*

Each of these is independently a meaningful improvement. Together they should eliminate the freeze category structurally, not by tuning.

---

## 2. Concrete deliverables

| # | File | Purpose |
|---|---|---|
| 1 | `Jools/Features/Chat/Snapshots/ActivitySnapshot.swift` | Value-type representation of an activity for the view layer |
| 2 | `Jools/Features/Chat/Snapshots/ActivitySnapshotBuilder.swift` | `ActivityEntity` → `ActivitySnapshot` converter (runs markdown pre-render) |
| 3 | `Jools/Features/Chat/Snapshots/FlatMarkdownRenderer.swift` | `String` → `[MarkdownSegment]` renderer (attributed string per text run + separate segments for code/table) |
| 4 | `Jools/Features/Chat/ChatView.swift` | Wire `ChatMessagesList` to use snapshots + `List` + stateless row views; keep `LiveChatChrome` / `LiveSessionStatusBanner` / observer wrappers already in place |
| 5 | `Jools/Features/Chat/Views/MarkdownText.swift` | Update to use the flat renderer (still usable for Preview and any non-cell contexts) |

No changes to: `ChatViewModel` (observable surface stays as-is), `PollingService`, `Entities.swift`, markdown parse cache (`ActivityContentDecodeCache`), any other screen.

---

## 3. Data model — `ActivitySnapshot`

```swift
/// Value-type projection of `ActivityEntity` for the SwiftUI list. The
/// view layer iterates these snapshots, NEVER the SwiftData entities,
/// so ForEach identity resolution + cell layout never touch the
/// SwiftData observation registrar.
struct ActivitySnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let type: ActivityType
    let createdAt: Date
    let isOptimistic: Bool
    let sendStatus: SendStatus
    let kind: Kind

    enum Kind: Equatable, Sendable {
        case userMessage(text: String)
        case agentMessage(segments: [MarkdownSegment])
        case planGenerated(snapshot: PlanSnapshot)
        case progressUpdated(snapshot: ProgressSnapshot)
        case planApproved
        case sessionCompleted(snapshot: CompletionSnapshot)
        case sessionFailed(message: String)
        case unsupported  // falls back to a compact "activity type" label
    }
}

struct PlanSnapshot: Equatable, Sendable {
    let steps: [PlanStepSnapshot]
}

struct PlanStepSnapshot: Equatable, Sendable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let status: StepStatus

    enum StepStatus: String, Equatable, Sendable {
        case pending, inProgress, completed
    }
}

struct ProgressSnapshot: Equatable, Sendable {
    let title: String?
    let descriptionText: String?
    let bashCommands: [BashCommandSnapshot]
    let messageSegments: [MarkdownSegment]
}

struct BashCommandSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let command: String
    let output: String?
    let success: Bool
}

struct CompletionSnapshot: Equatable, Sendable {
    let commitMessage: String?
    let diffAdditions: Int
    let diffDeletions: Int
    let changedFiles: [String]
    let prURL: String?
    let prTitle: String?
    let prDescription: String?
    let duration: TimeInterval
}
```

**Sendable conformance** is important — it means snapshot construction
can be moved off the main thread later if we need to. For the 3h spike
we'll build them on-main in the parent SwiftUI view, but the type is
ready to move.

**Equatable conformance** is what makes the `List` cell recycling
cheap: two snapshots with the same id and the same kind value are `==`,
and SwiftUI's diff can short-circuit cell updates.

---

## 4. Markdown rendering — flat segments

The existing `MarkdownText` view walks the swift-markdown AST and
produces a nested SwiftUI view tree (`VStack { ForEach { … } }`). The
new `FlatMarkdownRenderer` walks the same AST but produces a flat array
of `MarkdownSegment`s:

```swift
enum MarkdownSegment: Equatable, Sendable, Identifiable {
    case text(id: UUID, attributed: AttributedString)
    case codeBlock(id: UUID, language: String?, code: String)
    case table(id: UUID, head: [String], rows: [[String]])
    case thematicBreak(id: UUID)

    var id: UUID {
        switch self {
        case .text(let id, _), .codeBlock(let id, _, _), .table(let id, _, _), .thematicBreak(let id):
            return id
        }
    }
}
```

The `.text` case is the important one. It packs **multiple markdown
blocks** (paragraphs, headings, lists, blockquotes) into a single
`AttributedString` using paragraph-style attributes for indentation,
line spacing, and bullet prefixes. That turns what was a 5-level-deep
SwiftUI view subtree into a single `Text(attributed)`.

**Packing strategy:**

- Paragraph → attributed text + `\n\n` separator
- Heading (h1-h4) → attributed text with larger font + bold + `\n` separator
- Unordered list → each item as `• ` prefix + inline-built attributed text + `\n`
- Ordered list → each item as `N. ` prefix + inline-built attributed text + `\n`
- Blockquote → indented paragraph with left margin via `NSParagraphStyle`
- Inline (bold, italic, code, link, strikethrough) → existing `InlineAttributedStringBuilder` logic
- **Fenced code block** → breaks the text run, emits a separate `.codeBlock` segment, starts a new text run after
- **Table** → same as code block, separate `.table` segment
- **Thematic break** (`---`) → breaks the text run, emits `.thematicBreak`, new text run

**Result:** A typical agent message with 5 paragraphs + 1 table + 1 code block becomes 4 segments: `[text, table, text, codeBlock]` (two text runs sandwiching the non-text blocks). SwiftUI renders 4 views, not 50.

**Render:**

```swift
struct MarkdownSegmentView: View {
    let segment: MarkdownSegment

    var body: some View {
        switch segment {
        case .text(_, let attributed):
            Text(attributed)
                .textSelection(.enabled)
        case .codeBlock(_, let language, let code):
            FlatCodeBlockView(language: language, code: code)
        case .table(_, let head, let rows):
            FlatTableView(head: head, rows: rows)
        case .thematicBreak:
            Divider()
        }
    }
}
```

`FlatCodeBlockView` and `FlatTableView` are simple UIKit-style compact
views — `ScrollView(.horizontal)` + `Text` for code; `Grid` or
nested `HStack`+`VStack` for tables. These stay as SwiftUI because
they're genuinely structural.

---

## 5. Row-rendering surface

```swift
/// Stateless row view for a single activity. Holds NO observation;
/// takes the snapshot by value and renders.
struct ActivitySnapshotRow: View {
    let snapshot: ActivitySnapshot
    let canRespondToPlan: Bool
    let onApprovePlan: () -> Void
    let onRevisePlan: () -> Void

    var body: some View {
        switch snapshot.kind {
        case .userMessage(let text):
            UserMessageRow(text: text, sendStatus: snapshot.sendStatus, timestamp: snapshot.createdAt)
        case .agentMessage(let segments):
            AgentMessageRow(segments: segments, timestamp: snapshot.createdAt)
        case .planGenerated(let plan):
            PlanRow(plan: plan, canRespond: canRespondToPlan, onApprove: onApprovePlan, onRevise: onRevisePlan)
        case .progressUpdated(let progress):
            ProgressRow(progress: progress)
        case .planApproved:
            PlanApprovedRow()
        case .sessionCompleted(let completion):
            CompletionRow(completion: completion)
        case .sessionFailed(let message):
            FailedRow(message: message)
        case .unsupported:
            EmptyView()
        }
    }
}
```

Each `*Row` is a leaf view that reads ONLY from the snapshot. No
`@ObservedObject`, no `@Query`, no `@EnvironmentObject` for model data.
The `onApprovePlan` / `onRevisePlan` closures come from the parent, so
the plan row has no reference to `ChatViewModel` either.

---

## 6. List surface

```swift
struct ChatMessagesList: View {
    let session: SessionEntity
    @Bindable var viewModel: ChatViewModel
    @Query private var activities: [ActivityEntity]

    init(session: SessionEntity, viewModel: ChatViewModel) {
        self.session = session
        self.viewModel = viewModel
        let sessionId = session.id
        _activities = Query(
            filter: #Predicate<ActivityEntity> { activity in
                activity.session?.id == sessionId
            },
            sort: [SortDescriptor(\ActivityEntity.createdAt, order: .forward)]
        )
    }

    var body: some View {
        let snapshots = ActivitySnapshotBuilder.build(from: activities, fallback: session.activities)
        let effectiveState = session.effectiveState
        let canRespondToPlan = effectiveState == .awaitingPlanApproval
        let showsTyping = effectiveState == .running
            || effectiveState == .inProgress
            || effectiveState == .queued

        ZStack {
            if snapshots.isEmpty && viewModel.isLoading {
                ProgressView("Loading activities...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshots.isEmpty {
                EmptyActivitiesView(
                    state: effectiveState,
                    syncState: viewModel.syncState,
                    onRetry: { Task { await viewModel.manualRefresh() } }
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(snapshots) { snapshot in
                            ActivitySnapshotRow(
                                snapshot: snapshot,
                                canRespondToPlan: canRespondToPlan,
                                onApprovePlan: { viewModel.approvePlan() },
                                onRevisePlan: { viewModel.rejectPlan() }
                            )
                            .id(snapshot.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: JoolsSpacing.xs, leading: 0, bottom: JoolsSpacing.xs, trailing: 0))
                        }

                        if showsTyping {
                            TypingIndicatorView()
                                .id("typing-indicator")
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        MadeWithJoolsFooter()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await viewModel.manualRefresh() }
                    .accessibilityIdentifier("chat.scroll")
                    .onAppear { scrollToBottom(proxy: proxy, snapshots: snapshots, showsTyping: showsTyping) }
                    .onChange(of: snapshots.count) { old, new in
                        guard new > old else { return }
                        scrollToBottom(proxy: proxy, snapshots: snapshots, showsTyping: showsTyping)
                    }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, snapshots: [ActivitySnapshot], showsTyping: Bool) {
        if showsTyping {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        } else if let last = snapshots.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
```

**Critical differences from the current implementation:**

- `ForEach(snapshots)` iterates value types, not `ActivityEntity` — zero SwiftData keypath getters
- `List` instead of `ScrollView + LazyVStack` — native cell recycling
- Row body takes `ActivitySnapshot` by value — no observation surface
- Closures for approve/revise instead of passing viewModel down to the row

---

## 7. Snapshot builder (the one place we touch SwiftData)

```swift
enum ActivitySnapshotBuilder {
    /// Converts an array of `ActivityEntity` to `[ActivitySnapshot]`.
    /// Runs on the main actor because `ActivityEntity` is `@Model`
    /// (SwiftData types are main-actor by default). This is the ONE
    /// place in the chat surface that touches SwiftData properties;
    /// everything downstream is pure value types.
    @MainActor
    static func build(
        from query: [ActivityEntity],
        fallback: [ActivityEntity]
    ) -> [ActivitySnapshot] {
        let source = query.isEmpty ? fallback.sorted { $0.createdAt < $1.createdAt } : query
        return source.compactMap { entity in
            ActivitySnapshot(entity: entity)
        }
    }
}

extension ActivitySnapshot {
    @MainActor
    init?(entity: ActivityEntity) {
        self.id = entity.id
        self.type = entity.type
        self.createdAt = entity.createdAt
        self.isOptimistic = entity.isOptimistic
        self.sendStatus = entity.sendStatus
        guard let kind = ActivitySnapshot.Kind(entity: entity) else { return nil }
        self.kind = kind
    }
}

extension ActivitySnapshot.Kind {
    @MainActor
    init?(entity: ActivityEntity) {
        switch entity.type {
        case .userMessaged:
            self = .userMessage(text: entity.messageContent ?? "")
        case .agentMessaged:
            let segments = FlatMarkdownRenderer.render(entity.messageContent ?? "")
            self = .agentMessage(segments: segments)
        case .planGenerated:
            guard let plan = entity.plan else { return nil }
            let steps = (plan.steps ?? []).enumerated().map { i, step in
                PlanStepSnapshot(
                    id: i,
                    title: step.title ?? step.description ?? "Step \(i + 1)",
                    description: step.description,
                    status: PlanStepSnapshot.StepStatus(rawDTO: step.status)
                )
            }
            self = .planGenerated(snapshot: PlanSnapshot(steps: steps))
        case .progressUpdated:
            let segments = FlatMarkdownRenderer.render(entity.messageContent ?? "")
            let bash = entity.bashCommands.compactMap { dto -> BashCommandSnapshot? in
                guard let command = dto.command else { return nil }
                return BashCommandSnapshot(
                    id: UUID(),
                    command: command,
                    output: dto.output,
                    success: !dto.isLikelyFailure
                )
            }
            self = .progressUpdated(snapshot: ProgressSnapshot(
                title: entity.progressTitle,
                descriptionText: entity.progressDescription,
                bashCommands: bash,
                messageSegments: segments
            ))
        case .planApproved:
            self = .planApproved
        case .sessionCompleted:
            self = .sessionCompleted(snapshot: CompletionSnapshot(
                commitMessage: entity.messageContent,
                diffAdditions: entity.diffAdditions,
                diffDeletions: entity.diffDeletions,
                changedFiles: entity.changedFiles,
                prURL: nil,  // sourced from session in the row view
                prTitle: nil,
                prDescription: nil,
                duration: 0
            ))
        case .sessionFailed:
            self = .sessionFailed(message: entity.messageContent ?? "Session failed")
        case .unknown:
            return nil
        }
    }
}
```

**The markdown pre-render (`FlatMarkdownRenderer.render`) happens HERE**, at snapshot construction. The output `[MarkdownSegment]` is stored in the snapshot as a value type. The row view just reads it and displays. **There is no per-render markdown parsing in the view hot path.**

---

## 8. Stop conditions and pivot trigger

Hard timebox: **3 hours from the moment I start editing files.**

**Victory criteria** (to continue as the final fix):
- Build passes
- App runs
- `freeze-monitor.sh` v2 reports **<20% main thread busy** sustained over a 30-second aggressive scroll test on a live streaming session
- User can reproduce their normal workflow without the app hanging

**Pivot triggers** (abandon Option B, start Option A):
- Build doesn't pass at the 3-hour mark
- Monitor still reports >50% main thread busy under stress
- User reports a fresh freeze after the new build is installed

**Measurement plan:**
1. Install the Option B build on simulator
2. Run the existing `freeze-monitor.sh` in the background
3. Open a session, send the same markdown-stress prompt we used before, scroll through the response during streaming
4. Monitor should report sustained <20% busy
5. If numbers are good, also confirm on real device (Dhoomketu) before claiming victory

---

## 9. What gets deleted / simplified after Option B lands

If this works:
- The nested `MarkdownBlockView`, `ParagraphView`, `HeadingView`, `ListView`, `CodeBlockView`, `BlockQuoteView`, `TableView` in `MarkdownText.swift` become unused or only used by Preview. They can be simplified/removed.
- `ActivityView` (current router) is replaced by `ActivitySnapshotRow`.
- `AgentMessageBubble` (current) is replaced by `AgentMessageRow`.

If this doesn't work:
- The `FlatMarkdownRenderer` and `ActivitySnapshot` both transfer directly to Option A (UIKit pivot) — the `NSAttributedString` the renderer produces is the same thing `UIHostingConfiguration`-hosted cells or native UIKit cells would use.
- So no work is wasted.

---

## 10. Execution order

1. Create `Snapshots/` directory under `Jools/Features/Chat/`.
2. Write `ActivitySnapshot.swift` + `PlanSnapshot` etc.
3. Write `FlatMarkdownRenderer.swift` with unit-test-able pure function `render(_:String) -> [MarkdownSegment]`.
4. Write `ActivitySnapshotBuilder.swift`.
5. Add stateless row views (`AgentMessageRow`, `UserMessageRow`, `PlanRow`, `ProgressRow`, `CompletionRow`, `PlanApprovedRow`, `FailedRow`) — reusing existing SwiftUI subviews where they're already flat enough (e.g., `PlanCardView`, `CompletionCardView`, `CommandCardView`).
6. Update `ChatMessagesList` to use snapshots + `List`.
7. Build. Fix errors.
8. Install on sim. Run freeze-monitor. Stress-test.
9. Read the monitor output. If it holds, commit. If not, pivot.

I'm not going to append anything to this doc during implementation. This is the plan. If it changes, it changes in the commit message.
