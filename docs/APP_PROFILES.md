# App Profiles (Profile Generator)

> “Profile Generator” appears in the page heading only to explain the
> mechanism. Klik PRO never duplicates or copies an application bundle; it runs
> the original app under a separate profile. The related hardcoded ChatGPT /
> Codex & Claude Quick Launch feature is described in
> [`SPECIAL_FEATURE.md`](SPECIAL_FEATURE.md).

Klik PRO gives a supported app a **second, independent instance** —
its own profile with a separate login, history, and settings. Each profile appears
in the **App Profiles** tab and can be assigned to one of the four working mouse controls
so you can summon it in one action.

## What it will do

- ChatGPT and Claude are the first two generator cards and always remain visible,
  with an Installed or Not installed state.
- **Generate** opens a naming sheet, creates the isolated launcher, and
  opens it immediately.
- Klik PRO generates a small launcher and an isolated profile automatically.
- Existing launchers are listed without being converted or modified. Generated
  launchers can be renamed, repaired, archived, or restored. v1.2.1 maintenance
  never permanently deletes profile data.
- Every working mouse control chooses either Keyboard Shortcut or Open App. An
  occupied assignment requires Force Release & Assign.

## How it works

The launcher runs the **original, untouched app** pointed at a separate profile
directory (`--user-data-dir` for Electron/Chromium). The app in `/Applications`
is never copied, edited, or re-signed.

The generated launcher is a **small, separate `.app` bundle with its own bundle
identifier** (keyed by the instance UUID) and its own ad-hoc signature. It does
not impersonate the target. When it runs, it launches the untouched original app,
and **that running process keeps the original app's bundle identity, code
signature, and keychain access**. Because the second instance is the same original
bundle pointed at a different profile folder:

- It **survives app updates** automatically — it runs the live original, so it's
  always on the current version. Nothing to regenerate.
- **For a Verified app, the profile is tested to retain its login across
  relaunches and application updates** — the original bundle identity means the
  app's keychain entry still resolves.
- Archiving an instance removes its generated launcher and runtime access while
  preserving its profile, identity, assignments, and custom icon. The original
  app is untouched.

## Maintenance and recovery

Unlock **Advanced** to review managed profiles under **App Profile Maintenance**.
Klik PRO validates owned data separately from its generated launcher:

- **Healthy** profiles can be archived safely.
- **Missing Launcher** profiles can be repaired from their verified recipe and
  existing data.
- **Archived** profiles can be restored with the same UUID and saved appearance.
- **Missing Data** is reported without guessing, recreating, or deleting anything.

Archive and Restore are non-destructive lifecycle changes. Archived profiles do not
appear in normal profile lists and cannot own an active mouse mapping, hotkey, menu-bar
icon, or Open action. The configuration is authoritative; launchers and `vault.json`
are derived state and are reconciled after relaunch if an operation was interrupted.

## Approved app list

Detecting an engine does **not** prove an app works. The user therefore never sees
the full installed-app scan. Klik PRO shows only an installed app that matches a
compiled rule Aminudin has manually approved after testing. A match validates the
bundle ID, signing/Team ID, engine, and the app-specific isolation recipe.

- ChatGPT and Claude always occupy the first two generator cards.
- An installed card offers **Generate**; a missing card shows **Not installed**.
- Existing launchers appear under **Your App Profiles** with Open and Assign Button.
- Unsupported and merely detected apps are never listed.
- Future apps are added to the approved list only after Aminudin tests them.

Important caveats remain:

- A **direct-download** app can still be sandboxed and unable to reach a profile
  directory under Klik PRO's Application Support folder. Absence of an App Store
  receipt is **not** sufficient proof of eligibility.
- Engine is detected at generation time and re-checked at runtime — never cached
  authoritatively against a bundle ID.

## What's shared (by design)

Both instances are the same app to macOS, so these cannot be separated:

- one Dock tile and one `⌘Tab` entry,
- notifications attributed to the one app,
- one macOS permission set,
- OS-level window/switcher labels.

Klik PRO compensates with a per-instance **launcher (optionally pinned to the Dock
or menu bar) + hotkey + mouse button** — distinct ways to reach each instance, not
a distinct OS identity. This is the deliberate trade for being update-proof and
login-preserving.

## Why not a "clone" with its own Dock icon?

A clone (a copied bundle with a new bundle identifier, re-signed) would get a
separate Dock icon and permissions, but at the cost of manual regeneration on
every update, forced re-login, permission resets, and no App Store support. Klik
PRO **does not** do this — the launcher method keeps the login and survives
updates, which matters more for the target apps.

### Launcher vs. clone, side by side

| | Klik PRO (managed launcher) | Clone (separate bundle ID) |
|---|---|---|
| Modifies / copies the original | No | Yes (full copy, re-signed) |
| Survives app auto-updates | Automatically | No — manual regenerate |
| Always on the current version | Yes | No — frozen until regenerated |
| Retains sign-in | Verified per supported app | No — re-login (new identity) |
| Re-signing the target required | No | Yes, every generate |
| Separate Dock icon / `⌘Tab` entry | No (shared) | Yes |
| Per-instance notifications | No (shared) | Yes |
| Per-instance macOS permissions | No (shared) | Yes |
| Dedicated launcher + hotkey + mouse button | **Yes** | Not provided by the approach |
| Native (non-Electron) apps | Not supported | App-dependent (entitlements / app groups / keychain / provisioning can block it) |
| App Store / Apple-provisioned apps | Not supported | Not supported |
| Reversibility | Trivial | Delete bundle + profile |
| Ongoing maintenance | None | Regenerate on each update |

> **In short:** Klik PRO trades a separate Dock icon for an instance that is
> always current, retains sign-in (Verified per supported app), and needs no
> upkeep — then gives it a hotkey and a mouse button so you can still reach it
> instantly.

## Where things will live

```
~/Library/Application Support/Klik PRO/Launchers/<UUID>.app   # generated launcher (UUID-keyed)
~/Library/Application Support/Klik PRO/Profiles/<UUID>/       # isolated per-instance profile
~/Library/Application Support/Klik PRO/CustomIcons/<UUID>.icns # working custom icon
~/Library/Application Support/Klik PRO/config.json            # instance list (schema 12)
```

When a durable data folder is configured, new profiles instead use
`<Data Folder>/Instances/<UUID>/`, with `vault.json` manifest v2 at the folder root
and a portable `custom-icon.icns` beside the profile data when applicable.

Instances, their lifecycle, profiles, hotkeys, and button links are stored in
`config.json` schema 12. All structural
names are keyed by the instance **UUID**; the editable **label** is display-only
(the App Profiles row, menu-bar title, and the launcher's display name). Klik
PRO-created profiles live under `Klik PRO/Profiles/<UUID>` with an ownership
marker.

A pre-existing external ChatGPT/Claude Quick Launch wrapper is preserved as a
**legacy external** entry: Klik PRO keeps opening the original wrapper exactly
as before, and never inspects it, regenerates it, or claims ownership of its
profile data. Klik PRO does not convert, rename, move, or delete these existing
launchers.

## Replicating or adapting

The internal scan → engine-detect → structured-launcher foundation lives in
`Sources/Duplication/`. The legacy Quick Launch menu is data-driven from the
same instance list.
