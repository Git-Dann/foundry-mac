# macOS release — signing, notarization & DMG

How to produce a distributable Foundry for Mac build. Two paths: a **signed + notarized**
release (what end users get) and an **unsigned internal** build (when signing credentials
aren't available).

## Artifacts

`build-release.sh` + `make-dmg.sh` + `checksum.sh` produce, in `dist/`:

| File | Purpose |
|---|---|
| `Foundry.app` | the built, hardened-runtime app (universal: arm64 + x86_64) |
| `Foundry-<ver>-universal.dmg` | first-install DMG (signed) **or** |
| `Foundry-<ver>-universal-unsigned-internal.dmg` | first-install DMG (unsigned) |
| `Foundry-<ver>-universal.zip` | Sparkle update archive |
| `appcast.xml` | Sparkle feed (see [macos-updates.md](macos-updates.md)) |
| `*.sha256` | checksums |

`dist/` and all binaries are git-ignored — never commit them.

## Signed + notarized release

Prerequisites (one-time):

1. A **Developer ID Application** certificate in your login Keychain
   (Apple Developer → Certificates → Developer ID Application). Verify:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
2. A notarization credential — either an App Store Connect API key / Apple ID app-specific
   password. Store it once as a notarytool profile:
   ```bash
   xcrun notarytool store-credentials FoundryNotary \
     --apple-id "you@gitwork.co.uk" --team-id "<TEAM_ID>" --password "<app-specific-password>"
   ```

Then:

```bash
export APPLE_TEAM_ID="<TEAM_ID>"
Scripts/build-release.sh          # detects the Developer ID identity → signs, hardened runtime
Scripts/make-dmg.sh               # → Foundry-<ver>-universal.dmg (+ Sparkle .zip)
NOTARY_PROFILE=FoundryNotary Scripts/notarize.sh   # submit + staple + validate the DMG
Scripts/checksum.sh
```

`build-release.sh` signs with `--timestamp --options runtime` (hardened runtime is required for
notarization). `notarize.sh` runs `notarytool submit --wait`, then `stapler staple` + `validate`.

### Verify a signed build

```bash
codesign --verify --deep --strict --verbose=2 dist/Foundry.app
spctl -a -vv dist/Foundry.app
xcrun stapler validate dist/Foundry-<ver>-universal.dmg
spctl -a -vv -t open --context context:primary-signature dist/Foundry-<ver>-universal.dmg
```

## Unsigned internal build (no credentials)

If there's no Developer ID identity, `build-release.sh` automatically builds an **ad-hoc,
unsigned** app and `make-dmg.sh` names the DMG `…-unsigned-internal.dmg`. It runs on the
machine that built it (and others via right-click → Open / removing the quarantine flag), but
it is **not** notarized and Gatekeeper will warn on other Macs. Use it for internal testing only.

## Sandbox / entitlements

Foundry ships with the **hardened runtime** (required for notarization) but **without the App
Sandbox**. This is a deliberate, documented exception: Sparkle's in-place updater is far simpler
outside the sandbox, and DMG + Developer ID distribution (unlike the Mac App Store) doesn't
require sandboxing. Because every embedded binary (incl. Sparkle's framework + XPC services) is
signed with the same Developer ID, no extra entitlements are needed — the entitlements file is
intentionally minimal (`xcodegen` regenerates it). Adopting the sandbox (with Sparkle's XPC
services + mach-lookup exceptions) is a tracked v2 hardening task.

## What this does NOT touch

This flow is macOS-only. The web app deploys via Vercel and the iPhone app ships via App
Store/TestFlight from their own repos — both untouched.

## Required CI secrets

See [`.github/workflows/foundry-mac-release.yml`](../.github/workflows/foundry-mac-release.yml).
All are optional; absent ⇒ the workflow produces an unsigned internal DMG.

| Secret | Use |
|---|---|
| `APPLE_TEAM_ID` | signing + notarization team |
| `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` | notarization (Apple ID auth) |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` | base64 of the `.p12` |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` | `.p12` password |
| `SPARKLE_EDDSA_PRIVATE_KEY` | appcast signing — **never commit this** |
