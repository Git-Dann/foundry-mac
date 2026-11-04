# Foundry for Mac

A native macOS to-do app that is also your Foundry partner. Your own to-dos sit beside the
Foundry board tasks assigned to you, with your calendar and your client Slack, in one place.
Built with SwiftUI on macOS 26/27: system lists, forms, Liquid Glass controls, SwiftData,
Swift Charts and App Intents. Foundry may suggest the odd follow-up from your meetings;
nothing is added, sent or booked without you.

| Menu bar | Window | Widget |
|---|---|---|
| ![](docs/screenshots/menubar-light.png) | ![](docs/screenshots/window-light.png) | ![](docs/screenshots/widget-large-light.png) |
| ![](docs/screenshots/menubar-dark.png) | ![](docs/screenshots/window-suggestions-dark.png) | ![](docs/screenshots/widget-medium-dark.png) |

The data and the reading of your sources live in Foundry (Backstage → Commitments,
`Git-Dann/docs-by-gitwork`, `docs/commitments.md`). This app is a client of that API.

## What's in it

- **Planning views (Things-style).** Inbox (unsorted), Today with **This Evening**, Upcoming by
  day, Anytime, Someday, Logbook. Each to-do has a **When** (the day you'll do it) separate from
  its **Deadline**.
- **Lists** with colour, icon and area; drag a to-do onto a list in the sidebar. **Tags**
  (sidebar lists the most used). **Smart lists**: saved filters by list, tags, priority, due and
  words.
- **Detail pane.** Priority, repeat (daily, weekdays, weekly, fortnightly, monthly, yearly,
  every N days/weeks/months), a reminder at a time, a checklist with progress, and **rich
  notes** (bold, italic, headings, lists, checklists; stored as Markdown).
- **Quick add grammar.** `Call Valu about the quote #sales !! ~Clients every week fri 3pm`:
  tags, priority, list, repeat, day and time in one line; `tonight` and `someday` plan it.
- **Reorder** by dragging; **select several** for batch changes (Today, This Evening, Tomorrow,
  Someday, move to list, priority, done) from the toolbar or a right-click.
- **Board** (Kanban by list) and **Priorities** (Eisenhower matrix; drag between quadrants).
- **Focus timer** (15/25/50 minutes or custom, breaks, a live timer in the menu bar) and a
  **Focus filter**: in System Settings › Focus, a Focus can make Foundry show only today or
  only board tasks.
- **Habits** with streaks, a Mon–Sun check row and a 12-week chart (kept on this Mac).
- **⌘K command palette** to jump anywhere, open any to-do or run an action.
- **Foundry.** Board tasks assigned to you appear in your lists with their client; ticking one
  marks it done on the board. The Foundry view shows your Slack mentions and client channel
  messages (no AI) with "Make a to-do". Calendar shows your Google Calendar week.
- **Menu bar.** Today, This Evening, the next days and Inbox; quick add; the focus timer.
- **Works offline.** Edits are applied at once, queued and sent when Foundry is reachable.

## Keyboard

| | |
|---|---|
| ⌘K | Command palette |
| ⌘F | Search |
| ⌘N | New to-do (quick add in the window) |
| ⇧⌘N / ⌃⌥Space | Quick add (floating) |
| Space | Complete, accept or reopen the selected row |
| ⌘⌫ | Dismiss (while typing, it keeps its text meaning) |
| ⌘S | Snooze until tomorrow 09:00; in notes, save |
| ⌘R / ⇧⌘R | Refresh / check sources now |
| ⌘1–⌘9 | Inbox, Today, Upcoming, Anytime, Someday, Logbook, Calendar, Board, Priorities |

## Requirements

- Xcode 26 or later (built and tested here with Xcode 27 on macOS 27); runs on macOS 26+.
- `brew install xcodegen`.
- A Foundry server with the Commitments API (docs-by-gitwork PR #804). Against a server
  without it, the app says "Commitments aren't on this Foundry server yet."

## Install on your Mac

```bash
Scripts/install-local.sh
```

Builds Release, installs it to `/Applications` (the old copy goes to the Trash) and opens it.
It's signed ad hoc, so it runs only on this Mac and the widget can't read the app's data. Once
your Apple ID is in Xcode → Settings → Accounts, `TEAM=B27Y4M6S3Y Scripts/install-local.sh`
signs it with the GIT WORK team and the widget works too.

## Build and test

```bash
xcodegen generate
xcodebuild -project Foundry.xcodeproj -scheme Foundry -destination 'platform=macOS' build test
```

The unit tests cover the API contract (camelCase keys, `null` for cleared fields, tolerant
dates), grouping, the due-date parser, snooze times, the notification plan, the widget
snapshot, and the offline queue (edits survive a relaunch and are sent in order).

### Signing and the App Group

The widget reads the app's data through the App Group `group.co.gitwork.foundry`. Xcode only
signs an App Group with a provisioning profile, so **Debug builds leave it out** (they build
unsigned, but the widget shows "Open Foundry to sign in"). **Release** carries it and needs
the Developer ID identity, as `Scripts/build-release.sh` uses in CI. The entitlements files are
committed by hand and set per configuration in `project.yml`; xcodegen doesn't rewrite them.

### Against a running server

`LiveServerTests` drive the app's own API client, store and offline queue against a real
Foundry server. They're skipped unless you pass a mobile JWT:

```bash
TEST_RUNNER_FOUNDRY_IT_TOKEN=<jwt> TEST_RUNNER_FOUNDRY_IT_BASE=http://localhost:3100 \
  xcodebuild -project Foundry.xcodeproj -scheme Foundry -destination 'platform=macOS' test
```

They add, complete, delete and change settings, so use a local or throwaway server, never a
real production account (the test refuses `foundry.gitwork.co.uk`).

### Debug-only tools

- `--demo` runs the real app with sample data, no sign-in, network, notifications or widget writes.
- `--capture <dir>` saves the window, menu-bar panel, widget and quick-add views (light and
  dark) to PNGs. It uses the window server's image of the app's own windows, so it needs no
  Screen Recording permission. The menu-bar panel and widget are the real views hosted in a
  popover-material window, not the system's own chrome.
- `-api.baseURLOverride http://localhost:3100` and `-debug.keychainService <name>` point a
  debug run at another server with its own Keychain slot.

Each server keeps its own sign-in (`auth.mobileJWT` for production, `auth.mobileJWT@host:port`
otherwise), so a 401 from a local or preview server can never sign you out of production.

## Layout

```
Foundry/
  FoundryApp.swift        Scenes (window, menu bar, settings), keyboard commands
  App/                    AppModel, AppEnvironment
  Commitments/            Model, API client, store + offline queue, grouping, due-date parser
  UI/                     Menu-bar panel, window, detail, rows, settings
  System/                 Notifications, quick add + global hotkey, App Intents, widget feed
  Shared/                 Widget snapshot, App Group store, widget view (also in the extension)
  Services/               Sign-in, Keychain, network, Sparkle
  Debug/                  Screenshot capture and sample data (DEBUG builds only)
FoundryWidgets/           WidgetKit extension: Today
FoundryTests/             Unit and live-server tests
```

## Release and updates

Unchanged: [docs/macos-release.md](docs/macos-release.md) and
[docs/macos-updates.md](docs/macos-updates.md). Sparkle keeps updating installed copies.

## Conventions

- Bundle ID `co.gitwork.foundry`. Native frameworks only.
- System materials and controls only (Liquid Glass comes from them). No hand-made blur.
- Foundry Blue `#1D4ED8` is the accent only, lifted to `#6BA0FF` in dark mode for contrast.
- The API is camelCase. Never add a snake_case key strategy.
