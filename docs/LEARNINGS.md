# Learnings

Hard lessons earned building Jools. Appended to at the end of every
session so future work doesn't re-pay the same tuition.

**How to use this file:** if you hit a problem that looks similar to
an entry below, read the entry first before improvising. When a
session uncovers a new non-obvious lesson, add it under the relevant
section (or create a new one). Terse > verbose.

---

## SwiftUI performance

### LazyVStack in a chat-like surface is a trap

Under sustained scroll + polling, a `LazyVStack` walks every visible
cell's layout on each state invalidation, and with ~50 nested SwiftUI
views per markdown-rendered agent message, the main thread saturates
and the surface freezes.

**Fix pattern:** `SwiftUI.List` (backed by `UICollectionView` — real
cell recycling) + value-type row snapshots + a flat markdown
renderer that packs paragraphs / headings / lists / blockquotes into
a single `AttributedString` per text run, with separate segments only
for code blocks and tables. See `Jools/Features/Chat/Snapshots/`.

**Rule of thumb:** if a single message produces > 5 nested SwiftUI
views, flatten it. The Jules web UI emits ~3 flat HTML elements per
block — that's the target.

### @PersistedProperty reads from view bodies are a freeze vector

SwiftData entities are `@Model` reference types. Reading their
properties from inside a `View.body` registers an observation, and
every `@Query` update invalidates every such view. On a running
session with adaptive polling, that means near-constant invalidation
of the entire chat surface.

**Fix pattern:** snapshot-then-render. Build plain-value `Sendable`
structs in a `@MainActor` builder function, then hand those to the
views. The view layer never touches the entity. See
`ActivitySnapshot.swift` + `ActivitySnapshotBuilder.swift`.

### `@State + .animation(.repeatForever)` has re-render quirks

The classic SwiftUI idle-animation pattern (`@State` toggle +
`.animation(.repeatForever(autoreverses:), value:)`) can reset state
on parent re-render, and `easeInOut` gives you zero-velocity pauses
at each endpoint that read as "stuttering".

**Fix pattern:** for continuous periodic motion, use
`TimelineView(.animation)` + a time-driven `sin()`:

```swift
TimelineView(.animation(paused: !isAnimated)) { context in
    let t = context.date.timeIntervalSinceReferenceDate
    let y = amplitude * sin((2 * .pi / period) * t)
    content.offset(y: y)
}
```

No `@State`, no stuttering, phase-locked to the system clock. See
`JulesAvatarView.swift`.

### `GeometryReader` content isn't auto-clipped to its frame

A `GeometryReader { ... }.frame(width: 36, height: 36)` will constrain
the GR's proposed size but NOT clip what's drawn inside. Pixel art
with `.offset(y: -1)` animation will bleed above the frame, and if
the frame sits at the edge of a padded container, the animation will
visibly overshoot the container's border.

**Fix pattern:** either `.clipped()` the frame (but this can chop off
intentional shadows/overflow) OR give the frame enough parent padding
that ±amplitude never crosses the edge OR — usually best — move the
animation outside the GR and keep the GR a pure renderer.

---

## Animation / motion design

### Measure the reference, don't guess

When matching a reference animation (like the Jules web UI mascot
bob), extract frames and MEASURE amplitude + period before writing
code. A single-minute video can be reduced to a waveform via
`ffmpeg`'s `tile=N×1` filter applied to a 1-pixel vertical slit:

```bash
ffmpeg -i ref.mov -vf "crop=2:100:44:15,tile=717x1" -frames:v 1 timeline.png
```

The resulting image is a waterfall of vertical position over time.
Count cycles to get period, eyeball the band height to get amplitude.

**Rule of thumb for scaling:** an amplitude expressed as a RATIO of
mascot height (e.g. "12%") transfers across sizes better than a raw
pixel count.

### Industry-standard indeterminate progress patterns exist

Rolling your own linear sweeping-band progress indicator? Don't
autoreverse a sine — it creates zero-velocity pauses at each edge.
Use **linear sawtooth motion** (constant velocity, continuous
unidirectional sweep) and **two bands at 50% phase offset** so one
is always mid-sweep when the other is re-entering. This is the
CSS `animation: slide Xs linear infinite` pattern, used by GitHub,
Linear, Safari, Xcode, Material Design. See
`IndeterminateProgressStrip` in `SessionStatusBanner.swift`.

### Match motion semantics to what you're communicating

A progress strip tied to `PollingService.isPolling` (a bool that
flips true for 200-500ms per poll and false otherwise) reads as
"flash on, flash off, flash on". Because that's what it's tracking —
network-request state, not session state. Gate on the session state
instead: the strip sweeps continuously for the whole duration of
"Jules is working", not just the in-flight moments.

---

## UI testing on iOS

### `.descendants(matching: .any)` wedges the simulator under load

Whole-tree XCUITest queries (`app.descendants(matching: .any)[id]`)
walk the entire accessibility hierarchy. On a GitHub macos-15 runner
with the chat surface loaded, a single such query can blow the
30-second snapshot timeout, wedge the simulator, and cascade into
"Failed to terminate" / "Failed to launch" on every subsequent test
in the suite.

**Fix pattern:** always use a type-specific collection query:
`app.buttons[...]`, `app.staticTexts[...]`, `app.scrollViews[...]`.
If the identifier is landing on an element type you don't know,
drop the assertion entirely rather than falling back to `.any` —
the surrounding specific assertions are usually enough coverage.

### `.exists` is synchronous; use `.waitForExistence` after activation

`app.staticTexts["X"].exists` queries the CURRENT accessibility
snapshot. After `app.activate()` or any navigation, the snapshot may
not be fresh yet (especially on CI runners). The query returns false,
the test fails, cascade into wedged simulator.

**Fix pattern:** always use `.waitForExistence(timeout:)` after any
navigation or activation transition. `.exists` is only safe for
"already settled" assertions.

### CI runner variance is huge; don't optimize on noise

GitHub macos-15 runner performance varies by 2-3× between runs. A
"24-min" iOS test run might be a flaky simulator cascade, not a
slow run. Investigate the FAILURE MODE before restructuring the
workflow.

### `TimelineView(.animation)` starves XCUITest accessibility snapshots

**Symptom:** tests that were green yesterday start flaking with
`Failed to get matching snapshots: Timed out while evaluating UI
query`, then cascade into "Failed to terminate" / "Failed to launch"
in every subsequent test. `xcodebuild test` auto-retries, retries
pass, total wall time pushes past the job timeout.

**Root cause:** `TimelineView(.animation)` is a pure SwiftUI driver
that polls the system clock at ~60fps. It bypasses
`UIView.setAnimationsEnabled(false)` entirely, so UI tests that
set `JOOLS_UI_TEST_DISABLE_ANIMATIONS=1` still get continuous
per-frame view updates from any TimelineView in the view tree. On
CI runners (slower simulators, shared hardware), the continuous
updates prevent the accessibility snapshot from stabilising long
enough for XCUITest's query engine to complete — requests time
out, the simulator wedges, cascade.

**Fix pattern:** every `TimelineView(.animation)` site must gate
itself on the disable flag:

```swift
private static let animationsEnabled: Bool = {
    ProcessInfo.processInfo.environment["JOOLS_UI_TEST_DISABLE_ANIMATIONS"] != "1"
}()

var body: some View {
    if Self.animationsEnabled {
        TimelineView(.animation) { ... }
    } else {
        // static fallback — no driver, no updates
        staticContent
    }
}
```

Same applies to views that PASS `isAnimated: true` to a child that
uses TimelineView — check the env var in the view's init and force
`isAnimated = false` when the flag is set. See `JulesAvatarView`.

**Test when you add a new TimelineView:** run `make ui-test` and
watch for snapshot-timeout errors. If none, you're safe. If any,
gate the animation on the flag.

---

## CI workflow design

### Splitting iOS tests by target rarely wins

Each split test-job runner pays a full cold simulator boot
(~30-60s) + XCUITest bootstrap (~30s) + simctl warmup (20-100s on
cold runners). That's ~2-5 min of per-split overhead. Unless a
single test target dominates the runtime by minutes, the
parallelism savings won't cover the overhead.

**Default:** one iOS job. Build once, run all tests sequentially,
amortize sim boot across both targets.

### `xcodebuild test-without-building -xctestrun` can be slower than `xcodebuild test`

Measured on GitHub macos-15: the `-xctestrun` path took ~4 min
LONGER per test pass than the `-project`/`-scheme` path — despite
being equivalent on an M-series dev Mac. Likely some CI-runner code
path that re-initializes without scheme context. Stick to
`xcodebuild test` with `-project` / `-scheme` on CI.

### DerivedData cache is the real CI speedup

Warm builds skip ~90% of Swift compilation. Key the cache on:

```
${{ runner.os }}-xcode${{ xcodebuild_build_number }}-dd-${{ hashFiles('Jools/**/*.swift', ...) }}
```

Include the Xcode build number so compiler bumps invalidate cleanly
(otherwise stale module artifacts cause link errors).

### Shell logic → scripts, not YAML `run:` blocks

Inline bash inside GitHub Actions `run:` blocks can't be
shellchecked, can't be run locally to verify, and smells like
untestable glue. Extract logic to a `scripts/ci-*` file with
subcommand dispatch, shellcheck it, exercise each subcommand on a
dev machine before pushing the tag. See `scripts/ci-release`.

### Pre-release tags need special handling

iOS `MARKETING_VERSION` is `CFBundleShortVersionString` format —
pure `MAJOR.MINOR.PATCH`, no suffixes. A tag like `v1.0.0-alpha.1`
can't be written literally into `project.yml`. Split the tag into
numeric + prerelease parts in the release pipeline and compare
only the numeric portion against `MARKETING_VERSION`. Also remember
that `gh release download` without an explicit tag only matches
STABLE releases — pre-releases need the tag passed explicitly.

---

## Simulator / dev loop hygiene

### `xcrun simctl uninstall` wipes the keychain; overlay install doesn't

If you want to iterate on a live authenticated session:

- **Do**: `xcodebuild build` + `xcrun simctl install booted <.app>` —
  the app binary is replaced, keychain entries and SwiftData are
  preserved
- **Don't**: `xcrun simctl uninstall ... && make sim-install` — this
  wipes the keychain, forces the user to re-auth, and burns any
  in-memory state

### Test-mode fixtures ≠ real sessions

`JOOLS_UI_TEST_MODE=1` + `JOOLS_UI_TEST_SCENARIO=running-session`
loads seed fixtures, not real Jules data. Fine for UI test suites,
WRONG for "does this ship-able" verification. For feature
screenshots, regression testing of network edge cases, and "does
the fix actually work against production data", use a real
authenticated account.

### Keep the API key in `.env` so re-auth is programmatic

When a reinstall is unavoidable, read the key from `.env` (gitignored)
and pipe it into the simulator clipboard without echoing to stdout:

```bash
awk -F= '/^JULES_API_KEY=/ {print $2}' .env \
  | tr -d '\n' \
  | xcrun simctl pbcopy booted
```

Then automate the paste via `axe tap --label "Paste from Clipboard"`
+ `axe tap --label "Connect"`.

---

## iOS platform quirks

### `UIPasteboard.general.string` triggers the iOS privacy dialog

On iOS 16+, any custom button that reads `UIPasteboard.general.string`
triggers a system dialog asking the user to allow paste access — and
the default (bold) button in that dialog is **"Don't Allow Paste"**.
Users who tap quickly miss it entirely, the paste fails, the button
looks broken.

**Fix pattern:** use SwiftUI's `PasteButton(payloadType: String.self)`
which is a system-managed control and bypasses the dialog entirely.

### Simulator theme is separate from in-app theme override

`xcrun simctl ui booted appearance light|dark` sets the SYSTEM
appearance, but an app with its own theme override (like Jools's
`System / Light / Dark` setting in Settings → Appearance) ignores
the system value once the user has pinned a choice. To force a
theme during testing, go through the in-app picker.

---

## Collaboration with Claude

(Lessons about how Claude should work on Jools. Future-Claude:
read these before changing chat-surface or animation code.)

### Slow down. One change at a time.

Batching 5 changes and re-running the whole pipeline makes it
impossible to attribute regressions. When iterating on a visual bug:
make ONE change, verify in the real context, commit-or-revert, then
move to the next. `make sim-build && make sim-install && xcrun
simctl launch booted ...` is ~10s and preserves keychain. Use it
aggressively.

### When the user gives a directive, take it literally

If the user says *"just remove the rounded bubble. Just show the
avatar"*, the correct action is to remove the rounded bubble. Not to
add `.clipped()`, not to refactor the avatar layout, not to tweak
the HStack alignment. **Literal interpretation first. Ask questions
before extrapolating.**

### Verify in the real context, not the test fixture

A fix verified against `JOOLS_UI_TEST_SCENARIO=running-session`
means the fix works against seed data. A fix verified against a
live Jules session against the real API is what actually ships. For
anything visual or timing-sensitive, do the latter.

### Measure before tweaking animation parameters

Don't "bump the amplitude from ±1 to ±2 and see if it looks better".
Extract the reference animation into frames, measure amplitude and
period, compute a ratio, apply the ratio to your context. Guessing
wastes rebuild cycles and still lands in the wrong place.

### Update this file at the end of every session

If a session uncovered a non-obvious lesson — a SwiftUI quirk, a
simctl gotcha, an animation recipe, a failed CI approach — add it
here under the relevant section. Terse entries are better than
verbose ones. The goal is "future Claude reads this and saves 30
minutes".
