<p align="center">
  <img src="docs/jataayu-icon.png" alt="Jataayu" width="160" />
</p>

<h1 align="center">Jataayu</h1>

<p align="center">
  <a href="https://github.com/indrasvat/jataayu/actions/workflows/ci.yml">
    <img src="https://github.com/indrasvat/jataayu/actions/workflows/ci.yml/badge.svg" alt="CI" />
  </a>
</p>

<p align="center">
  <strong>Watch over Jules.</strong><br/>
  An unofficial iOS client for <a href="https://jules.google/">Google's Jules</a> — the autonomous coding agent.
</p>

---

Jataayu is a SwiftUI app that turns the public [Jules REST API](https://jules.google/docs/api/reference/) into a calm, mobile-first control plane. Triage what needs you, approve plans, watch progress, follow up in chat, and check the PR — all from your phone, while the actual coding work happens on Jules's Cloud VMs in the background.

This is **not** affiliated with Google. It's a side project that talks to the same public API any third-party Jules client would.

---

## Screens

|                          |                          |                          |                          |                          |
|:------------------------:|:------------------------:|:------------------------:|:------------------------:|:------------------------:|
| <img src="docs/screenshots/01-onboarding-light.png" alt="Onboarding screen in light mode with Connect to Jules button and key-capture options" width="180"/> | <img src="docs/screenshots/02-home-light.png" alt="Home dashboard in light mode showing Needs Attention summary and task suggestions" width="180"/> | <img src="docs/screenshots/03-sessions-light.png" alt="Sessions inbox in light mode listing active and completed Jules sessions" width="180"/> | <img src="docs/screenshots/05-plan-light.png" alt="Plan approval screen in light mode with expandable steps and Approve / Revise buttons" width="180"/> | <img src="docs/screenshots/04-diff-light.png" alt="Per-file diff viewer in light mode showing unified-diff hunks with additions and deletions" width="180"/> |
| <img src="docs/screenshots/01-onboarding-dark.png" alt="Onboarding screen in dark mode with Connect to Jules button and key-capture options" width="180"/> | <img src="docs/screenshots/02-home-dark.png" alt="Home dashboard in dark mode showing Needs Attention summary and task suggestions" width="180"/> | <img src="docs/screenshots/03-sessions-dark.png" alt="Sessions inbox in dark mode listing active and completed Jules sessions" width="180"/> | <img src="docs/screenshots/05-plan-dark.png" alt="Plan approval screen in dark mode with expandable steps and Approve / Revise buttons" width="180"/> | <img src="docs/screenshots/04-diff-dark.png" alt="Per-file diff viewer in dark mode showing unified-diff hunks with additions and deletions" width="180"/> |
| **Onboarding**            | **Home**                  | **Sessions inbox**        | **Plan approval**         | **Per-file diff**         |

Each screen reacts to your active system appearance and respects your in-app theme override (System / Light / Dark).

---

## What you can do today

These are flows that work end-to-end against the real public Jules API:

- **Connect** with your Jules API key (paste, or open Jules in an in-app Safari sheet and capture from clipboard)
- **Browse** every connected GitHub source and every session you've created
- **Triage** sessions from a Home screen that surfaces *Needs Attention* — anything waiting on your input or approval
- **Open a session**, see the full conversation timeline (agent and user messages, plans, progress updates, completion summaries)
- **Send follow-ups** with optimistic UI: your message appears instantly, then reconciles with the server activity once Jules acknowledges it
- **Approve plans** before Jules starts coding — tap once and watch the state machine roll over to *Running*
- **Watch live progress** via adaptive polling that uses the API's `createTime` filter for incremental fetches (with graceful fallback if the backend rejects it)
- **See PR output** when Jules opens a pull request, including the title and description
- **Schedule** repeating tasks via a native composer that hands off to the official Jules web flow when needed
- **Get notified** when a session needs plan approval, needs your input, completes, or fails — local notifications with a custom chime, driven by background app refresh when the app is suspended
- **Switch themes** in Settings (System / Light / Dark) — preferences persist across app launches

---

## Current limitations

Most of these are upstream constraints, not code we're avoiding writing.

| Limitation | Why |
|---|---|
| No scheduled-task CRUD inside the app | The public Jules REST API doesn't expose scheduled-task endpoints; we hand off to the web UI |
| No suggestions feed | Same — no public endpoint |
| No CI Fixer / Render / MCP integration management | No public endpoints for any of these |
| No media-artifact viewer | The DTOs we model only cover `bashOutput` and `changeSet` artifact types |
| No real-time push notifications | Local notifications via background refresh (~15-60 min intervals); sub-minute delivery would require a Jataayu-owned backend or upstream webhook support |

For more, see [`docs/Remaining_Work_Plan_2026-04.md`](docs/Remaining_Work_Plan_2026-04.md) and [`docs/Jools_Implementation_Plan_v3.md`](docs/Jools_Implementation_Plan_v3.md).

---

## Install

### Option A — try the latest release in a simulator (no Xcode build)

Each tagged release publishes a `Jataayu-vX.Y.Z-iphonesimulator.zip` asset on the [Releases page](https://github.com/indrasvat/jataayu/releases). The zip contains a Release-configuration `Jataayu.app` ready to drop onto a booted iPhone simulator.

```bash
# 1. Boot a simulator (any iPhone running iOS 26.0+) and wait for it to
#    finish booting. `bootstatus -b` blocks until the launchd tree is up.
xcrun simctl boot "iPhone 17 Pro" || true      # `|| true` — already-booted is not an error
xcrun simctl bootstatus "iPhone 17 Pro" -b
open -a Simulator

# 2. Grab the asset from the latest stable release.
gh release download --repo indrasvat/jataayu --pattern '*-iphonesimulator.zip'

# 3. Unzip and install.
unzip Jataayu-v*-iphonesimulator.zip
xcrun simctl install booted Jataayu.app
xcrun simctl launch booted com.indrasvat.jataayu
```

> **Installing a pre-release (e.g. alpha / rc)?** `gh release download` without an explicit tag only matches stable releases. For pre-releases, pass the tag by hand: `gh release download v1.0.0-alpha.1 --repo indrasvat/jataayu --pattern '*-iphonesimulator.zip'`.

This path doesn't require Xcode, signing, or any of the build dependencies — just a Mac with the iOS 26 simulator runtime installed.

### Option B — build and run on a physical device

Device builds need code signing with **your own** Apple Developer team. The project file ships pinned to the maintainer's team (`R65679C4F3`), so you'll need to override that the first time you open the project in Xcode (Signing & Capabilities → pick your team). Build via `make build-device`, then run from Xcode against a paired iPhone.

### Option C — build from source

For active development. See [Building from source](#building-from-source) below.

---

## Building from source

### Requirements

- macOS Sequoia or later
- Xcode 26.1+ (matches `xcodeVersion` in `project.yml`)
- iOS 26.0+ deployment target
- [Homebrew](https://brew.sh)

### One-shot setup

```bash
git clone git@github.com:indrasvat/jataayu.git
cd jataayu
./scripts/bootstrap     # installs SwiftLint, XcodeGen, Lefthook; resolves SPM; generates the Xcode project
make xcode              # opens the generated project in Xcode
```

### Common tasks

```bash
make build      # build for simulator (debug)
make test       # run JoolsKit + iOS app tests
make lint       # SwiftLint
make ci         # full CI pipeline (lint + JoolsKit + iOS build + tests)
```

A pre-push git hook (Lefthook) runs lint and a JoolsKit build before every push.

### Cutting a release

Releases are tag-driven — `make release` prepares the working tree and the [`release.yml`](.github/workflows/release.yml) workflow does the rest once the tag lands on GitHub.

```bash
make release VERSION=1.2.3   # bumps project.yml + adds CHANGELOG section
git diff                     # eyeball it
git add project.yml CHANGELOG.md
git commit -m "chore(release): v1.2.3"
git tag -a v1.2.3 -m "v1.2.3"
git push origin HEAD
git push origin v1.2.3       # this fires release.yml → publishes the GitHub Release
```

The release workflow validates the tag, cross-checks `MARKETING_VERSION`, builds a Release-configuration simulator app with `CODE_SIGNING_ALLOWED=NO`, zips it, and creates a GitHub Release with the matching `[VERSION]` block from [`CHANGELOG.md`](CHANGELOG.md) as the body.

### Getting an API key

The first launch shows the Onboarding screen. Tap **Connect to Jules** to open the Jules API key page in an in-app browser, copy the key, and Jataayu will offer to use it when you return to the app. You can also paste it manually via **I already have a key**.

---

## Architecture at a glance

```
Jools/                        SwiftUI app
├── App/                      App entry, dependency injection
├── Core/
│   ├── DesignSystem/         Pixel-J brand glyph, colors, typography, spacing, theme settings
│   ├── Navigation/           Root view, tab coordinator
│   ├── Notifications/        Local notification manager, state tracker (actor), background refresh, permission primer
│   └── Persistence/          SwiftData entities (Source, Session, Activity)
└── Features/                 Onboarding, Dashboard, Chat, CreateSession, Settings

JoolsKit/                     Swift package — pure networking + models
└── Sources/JoolsKit/
    ├── API/                  APIClient (actor), Endpoints, NetworkError
    ├── Auth/                 KeychainManager
    ├── Models/               Codable DTOs that mirror the Jules API
    └── Polling/              PollingService — adaptive cadence, foreground/background aware
```

- **MVVM** with `@MainActor` view models, no third-party reactive deps beyond Combine for a few publishers
- **Swift 6** with strict concurrency
- **Actors** for the API client and polling service
- **SwiftData** for the local cache of sources, sessions, and activities
- **SafariServices** for the OAuth-style key capture and the Jules web handoff flow

---

## Disclaimer

Jataayu is an independent third-party client. It is not built, sponsored, or endorsed by Google. *Jules* is a Google product and trademark; Jataayu talks to Jules's public REST API the same way any third-party client would. If you're looking for the official experience, that lives at [jules.google.com](https://jules.google.com).

## License

All rights reserved. The source is published for reference; no license to copy, modify, or redistribute is granted unless one is added in a subsequent commit.
