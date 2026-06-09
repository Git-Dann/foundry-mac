# Foundry — Apple product family

Foundry has two native Apple apps that share one hosted backend:

| | iPhone | Mac |
|---|---|---|
| Repo | `Git-Dann/foundry-ios` (on disk: `…/Documents/New project`) | `Git-Dann/foundry-mac` (this repo) |
| Tech | SwiftUI, iOS 26, xcodegen | SwiftUI, macOS 26, xcodegen |
| Bundle ID | `uk.co.gitwork.axisapp` (+ `.widgets`) | `co.gitwork.foundry` |
| Distribution | App Store / TestFlight | DMG + Sparkle |
| Auth | GoogleSignIn-iOS → `/api/auth/mobile-callback` | `ASWebAuthenticationSession` → `/api/auth/desktop/start` |
| Updates | App Store | Sparkle 2 (in-app) |

Both call the same API at `https://foundry.gitwork.co.uk` and use the **same per-user mobile
JWT** (`Authorization: Bearer …`, HS256 over `AUTH_SECRET`, audience `foundry-mobile`).

## Why separate apps (not Catalyst, not a ported iPhone app)

The Mac app is built **from scratch in SwiftUI for the Mac** — native windows, sidebar, toolbar,
menu bar, keyboard shortcuts, and Settings scene. A stretched iPhone UI (or Mac Catalyst) would
not feel like a first-class MacBook app, so Catalyst is intentionally **not** used. The iPhone
app keeps its touch-first UI, widgets, App Intents, Live Activities, and APNs — none of which
belong on (or port cleanly to) the Mac.

## What's shared vs platform-specific

The iPhone app's networking/auth/data layer is platform-agnostic and battle-tested against the
live API, so the Mac app **mirrors (copies + adapts)** it rather than sharing a package — the two
apps live in separate repos, so a duplicated, low-risk copy is safer than a premature shared
package. A future consolidation into local Swift packages (`FoundryCore` / `FoundryNetworking` /
`FoundryAuth` / `FoundryDesign`) is the natural next step once both apps live in one workspace.

**Mirrored from iOS (copied + adapted):**

- `NetworkClient` (URLSession async/await request layer) and the `APIRequest` shape.
- `KeychainService` → `KeychainStore` (distinct Mac service name `co.gitwork.foundry`).
- `AppError`, the model field shapes, and brand colours + the Icon Composer `AppIcon.icon`.

**Mac-only (built here):**

- The entire app shell + navigation, toolbar, menu commands, Settings scene.
- `WebAuthCoordinator` (ASWebAuthenticationSession) instead of GoogleSignIn-iOS.
- `UpdateController` (Sparkle) and the DMG/notarization scripts.
- The WebKit bridge (`FoundryWebView`).

**Deliberately NOT brought over:** iOS SwiftUI views, tab navigation, `PushNotificationService`
(APNs), `LiveActivityManager`, the `FoundryWidgets` extension, App-Group entitlements, and the
SwiftData offline store (the Mac app live-fetches in v1; an offline cache is a documented v2 item).

## Security note — the shared fallback token

The iPhone app's `AppConfig.swift` hard-codes a shared workspace bearer token
(`docsByGitworkBearerToken`) as a fallback. **The Mac app deliberately does NOT carry it** — it
authenticates with the per-user JWT only, so no shared server secret ships in the Mac binary.
(Removing that fallback from the iOS app is a separate, optional follow-up in the iOS repo.)

## Auth bridge (the one backend addition)

The only backend change for the Mac app is an additive, public route in the web repo:
`GET /api/auth/desktop/start`. It reuses the existing NextAuth Google login; once the user is
authenticated it mints the same mobile JWT (`signMobileToken`) and 302-redirects to
`foundry://auth-callback#token=…`, which `ASWebAuthenticationSession` captures. It does not touch
`/api/auth/mobile-callback` or any iOS behaviour.

## Why no Electron / Chromium / Node / bundled server

The Mac app is a real native app: SwiftUI + AppKit + WebKit + URLSession + Keychain + Sparkle.
There is no Electron, no bundled Chromium, no packaged Node runtime, and no local Next.js server.
WebKit appears only as a controlled, origin-restricted bridge for hosted screens not yet rebuilt
natively (e.g. the rich proposal editor).

## Why Metal is deferred

Metal was deferred because v1 has no GPU-heavy rendering workload. SwiftUI and AppKit provide the
native Mac UI path. Add Metal only if a real feature needs direct GPU rendering (e.g. a proposal
canvas or heavy document/PDF visual processing).
