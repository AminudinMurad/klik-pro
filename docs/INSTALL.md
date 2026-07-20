# Install / Local Setup

> Paths below use `YOUR_USERNAME` as a placeholder in log paths — adjust to your
> own home directory.

As of v1.1, the background input helper runs from a small **`Klik PRO Helper.app`**
bundle nested inside `Klik PRO.app` (rather than a bare binary in `~/bin`). This is
what makes the **Accessibility** entry show "Klik PRO Helper" with the app icon
instead of a raw executable name. A single per-user LaunchAgent runs that bundled
executable for all mouse mappings, menu icons, and optional quick-launch hotkeys.

## Install the pre-built release

### Verified Terminal installation

For releases with a signed checksum, download and inspect the repository's installer
before running it. Do not use a `curl | bash` command:

```zsh
curl --proto '=https' --tlsv1.2 -fLO \
  https://raw.githubusercontent.com/AminudinMurad/klik-pro/main/install.sh
less install.sh
chmod +x install.sh
./install.sh
```

Before changing `/Applications`, the installer verifies the checksum manifest with
Klik PRO's dedicated Ed25519 release key, validates the DMG checksum and structure,
checks the main and helper bundle identifiers, release versions, universal
architectures, and code-signature integrity, and asks for confirmation before
removing quarantine. It stages the new app and keeps the existing app as a temporary
rollback copy until post-install verification succeeds. Configuration and logs remain
untouched. The release-key fingerprint is:

```text
SHA256:Evg4ITqpPJY/aIT48Zv9Cp3psQfo977uCz/35a2k79E
```

Use `./install.sh --help` for a pinned version, local verification, alternate install
directory, or verification-only mode.

### Manual DMG installation

Download `Klik-PRO-vX.Y.Z-macos-universal.dmg` from the latest
[GitHub Release](https://github.com/AminudinMurad/klik-pro/releases/latest), open
it, then follow the large instruction in the Finder window: drag `Klik PRO.app`
onto the **Applications** shortcut. The normal user-facing install surface shows
only the app, Applications shortcut, and an **Extras** folder.

The **Extras** folder contains:

- `LaunchAgents/` — the combined background-service template
- `INSTALL.md` — this guide
- `LICENSE`
- `NOTICE.md` — reserved brand/artwork terms

The universal ZIP contains the same files as an alternative for users who prefer
an archive. After copying the app to `/Applications`, continue with Gatekeeper and
Accessibility below. Klik PRO installs its background-service definition
automatically.

## Build from source

Run the checked-in verification and release builder from the repository root:

```zsh
./tools/check.sh
./tools/build-release.sh
```

The builder compiles universal arm64 + x86_64 app/helper binaries with an explicit
macOS 13 deployment target, assembles both bundles, copies the icon and device
diagram, ad-hoc signs inner then outer bundles, verifies the archive, and writes:

```text
releases/Klik-PRO-vX.Y.Z-macos-universal.zip
releases/Klik-PRO-vX.Y.Z-macos-universal.zip.sha256
releases/Klik-PRO-vX.Y.Z-macos-universal.zip.sha256.sig
releases/Klik-PRO-vX.Y.Z-macos-universal.dmg
releases/Klik-PRO-vX.Y.Z-macos-universal.dmg.sha256
releases/Klik-PRO-vX.Y.Z-macos-universal.dmg.sha256.sig
releases/install-klik-pro.sh
releases/install-klik-pro.sh.sha256
releases/install-klik-pro.sh.sha256.sig
```

Official builds sign each checksum manifest with
`tools/sign-release-manifest.sh`. The private release key must remain outside the
repository; by default the builder looks for it at
`~/.config/klik-pro/release-signing/id_ed25519`. A contributor without that key can
still create a local build, but the builder labels its artifacts unsigned and the
official installer correctly refuses them. The distributable public key is checked in
as `release-signing-key.pub` and must match the copy embedded in `install.sh`.

The checked-in device preview and every app-icon representation are generated from
the same opaque frosted-white mouse master at `assets/Klik PRO mouse.png`. Regenerate
all artwork deterministically with:

```zsh
./tools/render-artwork.sh
```

The callout coordinates in `Sources/KlikProApp.swift` are tuned to that exact
1000×742 crop. `./tools/check.sh` verifies the generated device image, 1024px icon
master, 400px README icon, and all ten standard ICNS representations.
Run `./tools/render-previews.sh` after UI or device-diagram changes to refresh both
README screenshots with an isolated default config.

## Opening a non-notarized build (Gatekeeper)

Klik PRO is **not notarized or signed with an Apple Developer ID** — it's an
ad-hoc-signed, self-built utility. How macOS treats it depends on where the app
came from:

- **You built it yourself** (the source-build steps above): locally compiled bundles are not
  quarantined, so Gatekeeper generally won't block them. You still need to grant
  Accessibility (below).
- **You downloaded a pre-built copy** (the release DMG or ZIP): the download is tagged
  with `com.apple.quarantine`, so on first launch macOS shows *"Klik PRO can't be
  opened because Apple cannot check it for malicious software."* This is expected.

### Option A — approve it in System Settings (recommended)

1. Double-click `Klik PRO.app`. The warning appears — click **Done** (do not move
   it to Trash).
2. Open **System Settings → Privacy & Security**, scroll to the **Security**
   section. You'll see *"Klik PRO was blocked to protect your Mac."*
3. Click **Open Anyway**, authenticate, then confirm **Open** in the follow-up dialog.

(On macOS 15+ the old right-click → **Open** shortcut no longer bypasses Gatekeeper
for unsigned apps — use the Settings flow above.)

### Option B — clear the quarantine flag from Terminal

```zsh
xattr -dr com.apple.quarantine "/Applications/Klik PRO.app"
```

The nested helper is inside the app bundle, so clearing the app's quarantine covers
it too. Only do this for builds you trust (e.g. your own, compiled from this source).

> Note: clearing quarantine is about *launching* the app. It is separate from the
> **Accessibility** permission the input helper needs — you must still grant that
> (below), and re-grant it after every rebuild.

## Background services

Klik PRO automatically creates one per-user LaunchAgent when the settings app opens.
It repeats that check before Accessibility setup, enabling launch at login, or
enabling the Special Feature. No copying, username editing, or Terminal command is
required for a normal DMG or ZIP installation.

The combined service runs the nested helper at the app's actual installed path. It
owns mouse mappings, the persistent Klik PRO status icon, and (when Special Feature
is enabled) the ChatGPT / Codex and Claude launcher icons and hotkeys. Its two green
button dots appear only after the Accessibility event tap is operational.
When upgrading from a release that installed a separate menu helper, Klik PRO unloads
and removes that legacy LaunchAgent automatically.

The `LaunchAgents/` folder included in release downloads contains readable templates
for manual recovery only. If automatic setup reports an error, make sure
`Klik PRO.app` is in `/Applications`, reopen it, and try **Set Up Accessibility…**
again. As a last-resort recovery, copy and edit the templates before loading them:

```zsh
cp LaunchAgents/local.klik-pro.input.plist ~/Library/LaunchAgents/
# Replace YOUR_USERNAME in the file with your macOS username first.

launchctl enable gui/$(id -u)/local.klik-pro.input
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.klik-pro.input.plist
```

## Check running state

```zsh
launchctl print gui/$(id -u)/local.klik-pro.input
```

## Accessibility

The input helper needs Accessibility permission. A new installation opens Klik PRO's
one-screen welcome guide automatically; click **Set Up Accessibility…** there. You can
also select the **Settings** tab and use the same action later. Klik PRO first installs
its background services, starts the real nested helper if necessary, asks that helper
to register its own permission request, and opens **System Settings → Privacy &
Security → Accessibility**. The generated entry appears as **"Klik PRO Helper"** with
the Klik PRO icon. macOS requires you to turn it on yourself; apps cannot grant this
permission automatically.

To repeat onboarding or repair a stale approval, click **Reset Accessibility…** in
the same Settings card and confirm **Reset and Set Up Again**. Klik PRO clears its
helper approval, restarts the helper, and reopens the welcome guide. Choose
**Set Up Accessibility…** to return to the correct macOS pane. Mouse mappings remain
paused until you turn **Klik PRO Helper** back on.

If the guided action cannot create the entry, use the manual fallback: click `+`, press
⌘⇧G, and paste:

```text
/Applications/Klik PRO.app/Contents/Helpers/Klik PRO Helper.app
```

then toggle it on. **The grant drops every time you rebuild** (ad-hoc code signing
changes on each build). Use **Set Up Accessibility…** again after a rebuild; if the old
entry remains stale, remove it first and repeat the guided action. The running helper
retries automatically after permission is granted, so a manual restart is normally
unnecessary.

## MX Master 3 Gesture Button and keyboard app switching

The tested MX Master 3 Mac reports its physical Gesture Button as `⌘Tab`. Klik PRO
does not intercept that keyboard shortcut. Instead, while Gesture is enabled, the
input helper applies a device-scoped macOS HID key map only to Logitech device
`0x046D:0xB023`: Tab becomes F20 on that mouse service, and Klik PRO handles the
resulting `⌘F20` sentinel. A real keyboard `⌘Tab` stays unchanged for normal app switching.

The helper refuses to overwrite an existing non-empty `UserKeyMapping` on that
device. It clears only its own exact Tab-to-F20 map when Gesture or launch-at-login
is disabled, and on a clean helper stop. No Input Monitoring grant is required.

If the helper stopped uncleanly, use its ownership-aware cleanup command. It clears
only the exact map Klik PRO marked as its own and refuses unknown/custom maps:

```zsh
"/Applications/Klik PRO.app/Contents/Helpers/Klik PRO Helper.app/Contents/MacOS/klik-pro-input" \
  --clear-gesture-map
```

Do not use a raw `hidutil --set '{"UserKeyMapping":[]}'` cleanup without first
inspecting the device: that command replaces every custom key map on the matched
mouse service.

Mouse reconnects are observed automatically. If Gesture still does not resume,
restart the input helper:

```zsh
launchctl kickstart -k gui/$(id -u)/local.klik-pro.input
```

## Logs

```text
~/Library/Logs/klik-pro-input.log
~/Library/Logs/klik-pro-input.error.log
~/Library/Logs/klik-pro-events.log
```

## Config

```text
~/Library/Application Support/Klik PRO/config.json
```

Written with defaults on first run; if it exists but fails to decode, the input
helper falls back to defaults in memory only — it won't overwrite the file, so you
can inspect or fix it by hand.
