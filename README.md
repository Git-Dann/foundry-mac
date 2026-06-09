# Foundry for Mac

A native **SwiftUI macOS 26** app for [Foundry](https://foundry.gitwork.co.uk) (Gitwork's
agency platform). It talks to the same hosted API as the web app and the iPhone app — the
backend and database stay remote, and **no server secret ships in the app**.

> This is a standalone repo. The web app (`Git-Dann/docs-by-gitwork`) and the iPhone app
> (`Git-Dann/foundry-ios`) are separate and untouched. See
> [docs/apple-product-family.md](docs/apple-product-family.md).

## Download

First install is a DMG from the **[latest release](https://github.com/Git-Dann/foundry-mac/releases/latest)**.
After that, Foundry updates itself in place via Sparkle (see [docs/macos-updates.md](docs/macos-updates.md)).

> DMGs and Sparkle update archives are published as **release assets** — they are not committed
> to the repo (binaries are git-ignored). The public download page also links the latest DMG at
> `foundry.gitwork.co.uk/download`.

## Highlights

- **Native shell** — `NavigationSplitView` sidebar, unified toolbar, menu commands, keyboard
  shortcuts (⌘N / ⌘R / ⌘F / ⌘L / ⌘,), and a native Settings scene.
- **Liquid Glass, the Apple way** — provided automatically by the standard system components
  (sidebar, toolbar, sheets, controls). No custom blur/opacity/shadow "glass".
- **Native CRUD** for Proposals, Clients, Rate Card, plus CodeClear browse — over `URLSession`
  + async/await against the documented Foundry API.
- **Secret-free auth** — sign in via `ASWebAuthenticationSession` against the real Foundry
  Google login; the server mints the existing per-user mobile JWT and hands it back through a
  `foundry://` callback. The token lives in the macOS Keychain.
- **Controlled WebKit bridge** — hosted screens (e.g. the rich proposal editor) open in an
  in-app `WKWebView` window restricted to Foundry origins; external links go to the browser.
- **In-app updates via Sparkle 2** — install once from a DMG, then updates arrive (and are
  EdDSA-verified) inside the app.

## Requirements

- **Xcode 26** (macOS 26 SDK) and **macOS 26.0+**.
- [`xcodegen`](https://github.com/yonggit/XcodeGen) — `brew install xcodegen`.

## Run locally

```bash
xcodegen generate                       # generate Foundry.xcodeproj from project.yml
open Foundry.xcodeproj                   # ⌘R in Xcode, or:
xcodebuild -project Foundry.xcodeproj -scheme Foundry -configuration Debug \
  -destination 'platform=macOS' build
xcodebuild -project Foundry.xcodeproj -scheme Foundry -destination 'platform=macOS' test
```

The Xcode project is generated and **git-ignored** — always run `xcodegen generate` first.
Point the app at a non-production deployment from **Settings → API** (no rebuild needed).

## Build a DMG

```bash
Scripts/build-release.sh    # archive + export (signed if a Developer ID identity exists, else unsigned)
Scripts/make-dmg.sh         # → dist/Foundry-<ver>-universal[-unsigned-internal].dmg + a Sparkle .zip
Scripts/checksum.sh         # → SHA-256 sidecars
```

- **Signed + notarized release:** see [docs/macos-release.md](docs/macos-release.md).
- **Publishing an update via Sparkle:** see [docs/macos-updates.md](docs/macos-updates.md).

## Layout

```
Foundry/
  FoundryApp.swift         App entry, scenes, commands wiring
  App/                     AppModel, AppEnvironment, AppCommands
  DesignSystem/            Theme (brand colours), state views, formatting
  Features/                Dashboard · Proposals · Clients · CodeClear · RateCard · Settings + shell
  Services/                FoundryAPIClient, AuthStore, KeychainStore, WebAuthCoordinator,
                           UpdateController (Sparkle), NetworkClient, NetworkMonitor
  Models/                  Codable DTOs + inputs
  Web/                     FoundryWebView + origin policy (the WebKit bridge)
  Intents/                 App Intents (Open / Create / Search + entities)
  Resources/               Assets.xcassets, AppIcon.icon, Info.plist, entitlements
FoundryTests/              Unit tests (decoding, dates, JWT, callback parsing, environment)
Scripts/                   build-release · make-dmg · notarize · checksum · generate-appcast · publish-update
.github/workflows/         foundry-mac-release.yml (Mac-only CI)
```

## Conventions

- **Bundle ID** `co.gitwork.foundry`. (The iPhone app uses `uk.co.gitwork.axisapp`; if you want
  family consistency, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to `uk.co.gitwork.foundry`.)
- **No Electron, no Chromium, no Node, no bundled Next.js server.** Native frameworks only.
- **No Mac Catalyst** — this is a from-scratch Mac UI, not a ported iPhone app.
- **No Metal** — v1 has no GPU-heavy rendering workload; SwiftUI + AppKit provide the native UI path.
