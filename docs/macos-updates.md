# macOS updates — Sparkle 2

Foundry uses [Sparkle 2](https://sparkle-project.org) for in-app updates: users install once
from a DMG, and every later version is delivered + installed inside the app. Sparkle is Mac-only
(it is not in the iPhone app, and its private key is never committed).

## How it's wired

- Sparkle is added via **Swift Package Manager** (`project.yml` → `packages.Sparkle`).
- `Services/UpdateController.swift` wraps `SPUStandardUpdaterController` and exposes
  `canCheckForUpdates`, `checkForUpdates()`, and the automatic-check preference.
- **Check for Updates…** is in the app menu (`App/AppCommands.swift`); the same controls live in
  **Settings → Updates**, including the auto-check toggle.
- Info.plist carries:
  - `SUFeedURL` — the appcast URL (defaults to the GitHub Releases `appcast.xml`).
  - `SUPublicEDKey` — the EdDSA **public** key (a valid-base64 placeholder is committed; the real
    key is set at release, see below).
  - `SUEnableAutomaticChecks` = true, `SUScheduledCheckInterval` = 86400.

## One-time: generate signing keys

EdDSA keys sign update archives so the app only installs authentic updates.

```bash
# Sparkle's tools are fetched by SwiftPM; find them after a build:
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin' -type d | head -1)"

"$SPARKLE_BIN/generate_keys"        # creates the private key in your Keychain, prints the public key
```

1. Copy the printed public key into `Foundry/Resources/Info.plist` → `SUPublicEDKey`
   (replacing the `AAAA…=` placeholder). Commit that — the **public** key is safe to commit.
2. Keep the **private** key safe. For CI, export it and store it as the `SPARKLE_EDDSA_PRIVATE_KEY`
   secret — **never commit it** (it's git-ignored):
   ```bash
   "$SPARKLE_BIN/generate_keys" -x sparkle_private_key.txt   # then paste into the CI secret, then delete
   ```

## Publish an update

Bump the version (both in `project.yml`): `MARKETING_VERSION` (semantic, e.g. `0.2.0`) and
`CURRENT_PROJECT_VERSION` (incrementing integer). Then:

```bash
Scripts/build-release.sh
Scripts/make-dmg.sh
Scripts/generate-appcast.sh      # signs the .zip with the EdDSA key → dist/appcast.xml
Scripts/checksum.sh
Scripts/publish-update.sh        # uploads DMG + .zip + appcast.xml to GitHub Releases (mac-v<ver>)
```

`generate-appcast.sh` feeds **only the Sparkle `.zip`** to Sparkle's `generate_appcast` (the DMG
is first-install only — mixing both trips Sparkle's "duplicate updates" guard), and writes a
signed `appcast.xml` whose enclosure URL points at the release asset. Existing installs pick it
up on their next check.

> The private key comes from the Keychain locally, or from `SPARKLE_EDDSA_PRIVATE_KEY` in CI
> (the script writes it to a temp file and passes `--ed-key-file`).

## Keeping the web /download page current

`publish-update.sh` finishes by calling **`Scripts/update-download-page.sh`**, which writes
`public/desktop/latest-mac.json` in the **web repo** (`Git-Dann/docs-by-gitwork`) — version,
build, the release DMG URL, sha256, notarized flag — and **opens a PR** there via the GitHub
Contents API (no clone). Merge it → Vercel redeploys → `foundry.gitwork.co.uk/download` shows the
new build. No hand-editing of the metadata.

- **Local:** runs automatically inside `publish-update.sh` (needs `gh` with write access to the
  web repo). Run it standalone any time with `Scripts/update-download-page.sh`.
- **CI:** the release workflow runs it on `mac-v*` tags when the **`DOCS_REPO_TOKEN`** secret is
  set (a PAT with `repo` scope on the web repo — the default `GITHUB_TOKEN` can't write to another
  repo). Absent ⇒ the step is skipped.
- **Options:** `DIRECT=1` commits straight to the web repo's `main` (auto-deploys, no PR);
  `DRY_RUN=1` prints the JSON without making changes.

Updates installed *inside* the app still come from Sparkle — `/download` is first-install only.

## Update hosting

Default: **GitHub Releases** on the Mac repo. `SUFeedURL` →
`https://github.com/Git-Dann/foundry-mac/releases/latest/download/appcast.xml`, with enclosure
URLs at the same `releases/latest/download/` prefix (set via `DOWNLOAD_URL_PREFIX` in
`generate-appcast.sh`).

To self-host instead (e.g. `https://foundry.gitwork.co.uk/desktop/`): change `SUFeedURL` in
Info.plist and `DOWNLOAD_URL_PREFIX`, and upload `appcast.xml` + the `.zip` there.

## Test updates

1. Set a **lower** local `CURRENT_PROJECT_VERSION` (e.g. build `1`) and run the app.
2. Publish an appcast advertising a higher version (against a test feed).
3. **Foundry → Check for Updates…** should find it; with auto-checks on it appears on schedule.
4. Confirm the appcast has signatures:
   ```bash
   grep -c 'sparkle:edSignature' dist/appcast.xml     # → 1 per update
   ```

> A signature only appears when the archive's embedded `SUPublicEDKey` matches the signing key —
> i.e. once you've replaced the placeholder with your real public key and rebuilt.
