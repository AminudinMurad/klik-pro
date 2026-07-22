# Changelog

All notable changes to Klik PRO are documented here.

## 1.2.8

A focused Advanced cleanup hotfix.

- **Deep Scan reports markerless data folders** — UUID-named profile folders that
  no longer have Klik PRO ownership markers are shown as manual-review leftovers
  instead of letting Deep Scan report everything clean.
- **Scan & Adopt picker width fixed** — the vault-folder picker now uses compact
  wording so macOS no longer stretches the file picker across the screen.

## 1.2.7

A focused polish update for App Profile custom icons and cleanup feedback.

- **Custom PNG icons fill the Dock tile** — user-chosen PNG/ICO artwork is now
  shaped into the full macOS app-icon canvas instead of being inset inside a
  second rounded square, so generated Dock and Launchpad icons look larger and
  cleaner.
- **Clearer leftover cleanup guidance** — partial cleanup results now explain that
  a related app may still be holding profile data open, and suggest quitting that
  app or restarting macOS before scanning again.

## 1.2.6

A focused correction for owner-enabled ChatGPT App Profiles created in v1.2.5.

- **ChatGPT Dock and Launchpad launch fixed** — generated launchers now accept the
  same explicit production-rule eligibility as profile creation and the working
  menu-bar runtime. Owner-enabled Untested rules remain visibly Untested, while their
  exact signed bundle, Team ID, engine, persisted rule ID, and isolation paths are
  revalidated before every launch.
- **Fail-closed rule matching retained** — generic Experimental engine detections,
  unsupported apps, removed rules, and mismatched persisted rule IDs remain rejected.

## 1.2.5

Completes App Profile removal cleanup and adds a safe, ownership-gated scan for
artifacts left behind by profiles that are no longer tracked.

- **Reliable menu-bar profile icons** — the helper now uses the configured durable
  data-folder root when checking managed profiles, so vault-backed profiles remain
  launchable and receive their menu-bar icons.
- **Clearer Advanced removal choice** — **Delete Data** now offers **Remove Icons
  (Keep Data)** or **Delete All Data**. Both clear the generated launcher and its Dock,
  Launchpad, and menu-bar presence; only Delete All Data removes validated login and
  profile data.
- **Complete owned-artifact cleanup** — removal also clears the profile's persisted
  custom-icon copy and advisory lock file, including profiles stored in a durable data
  folder. Launch Services is unregistered after a launcher is removed.
- **Deep Scan for Leftovers** — Advanced can find marker-owned orphaned profile data,
  UUID-keyed custom icons and lock files, safely generated launchers, and missing Dock
  tiles that point directly into Klik PRO's managed launcher folder.
- **Recoverable by default** — deep-clean results can be moved to Trash. Permanent
  deletion remains behind a separate destructive confirmation; ambiguous or
  markerless data is excluded.
- **Accurate cleanup reporting** — stale Dock tiles count as removed only after the
  Dock preference update succeeds and the old path is no longer present.

## 1.2.4

Smooths the after-update Accessibility re-grant so the helper's toggle can be summoned
with one click.

- **"Register Helper" button** — the after-update Accessibility guidance dialog now has
  a **Register Helper** button that makes the current Klik PRO Helper's Accessibility
  toggle appear immediately, instead of waiting for it to show up or trying to add it
  with "+". Because the helper lives inside the app bundle, it cannot be added by hand
  with "+"; the button re-registers the helper so macOS lists — and prompts for — the
  correct entry. The dialog wording no longer instructs the user to use "+".

## 1.2.3

A maintenance update that improves App Profile repair detection and adds hover help
throughout the permission and maintenance controls.

- **Smarter repair detection** — a managed App Profile whose launcher exists but whose
  source app or embedded runtime no longer matches the recorded compatibility rule is
  now surfaced as **Repair** in Advanced instead of reporting Healthy. Repair rebuilds
  only the generated launcher; login and profile data are never touched.
- **Renamed vendor frameworks recognised** — the ChatGPT/Codex app's renamed
  `Codex Framework.framework` is accepted as a valid Electron engine hint. Registry
  identity and signing checks still gate compatibility.
- **Hover tooltips** — the Settings tab's Accessibility controls (Open Accessibility,
  Recheck, Reset Access) and every App Profile Maintenance action (Repair, Restore,
  Archive, Forget, Delete Data) now show a short hover tooltip explaining what they do.
- **Documentation** — the README gains a dedicated Advanced tab section and a
  Permissions controls reference.

## 1.2.2

This release completes App Profile cleanup and recovery with explicit, fail-closed
controls for stale records and owned data left behind on disk. It is an important
corrective update for v1.2.1 users who store profiles in a selected durable Data Folder.

- **Important v1.2.1 Data Folder launch fix** — v1.2.1 generated launchers incorrectly
  required the default Application Support profile path, so newly created profiles in
  a selected durable Data Folder could fail to launch. v1.2.2 signs the exact validated
  storage type and profile path into new launchers and refreshes older managed launchers
  when they are used. Profiles kept in the default Application Support location were
  not affected by this defect.

- **Forget stale entries** — remove a Missing Data record and its derived launcher
  without guessing at, recreating, or deleting user data.
- **Find orphaned data** — scan Klik PRO's managed Application Support and durable
  data-folder roots for UUID-keyed data that no longer has a trustworthy record.
- **Safe reclaim controls** — marker-owned orphaned data can be moved to Trash or,
  after a separate destructive confirmation, permanently deleted. Markerless,
  ambiguous, symlinked, or in-use paths fail closed.
- **Partial-failure reporting** — multi-artifact cleanup reports each result and
  retains the profile record unless every validated artifact was removed.
- **Fixed vault-backed launchers** — generated Dock, Spotlight, Launchpad,
  and Finder launchers now validate and open profiles stored in the selected durable
  data folder instead of incorrectly requiring the Application Support profile path.
- **Clearer removal choices** — **Remove from Klik PRO** keeps login/profile data on
  disk, while **Delete Data** explicitly removes the launcher, managed entry, and
  validated profile data using Move to Trash or a separately confirmed permanent delete.

## 1.2.1

This release gives App Profiles a focused, non-destructive maintenance workflow.
It makes stale entries understandable and repairable without risking saved logins.

- **App Profile Maintenance in Advanced** — managed profiles now report a clear
  state: Healthy, Missing Launcher, Missing Data, or Archived.
- **Repair Launcher** — rebuilds a missing generated launcher from verified profile
  data while keeping the same profile UUID, login, settings, and custom icon.
- **Archive and Restore** — Archive removes the generated launcher and deactivates
  runtime assignments without deleting profile data. Restore regenerates the same
  profile later, subject to the normal assignment-conflict checks.
- **Portable custom icons** — profiles stored in a durable data folder retain a
  recovery copy of their custom icon alongside their owned data.
- **Safer recovery** — configuration schema 12 and vault manifest v2 preserve
  lifecycle and appearance metadata. Launch-time reconciliation repairs derived
  manifest state and completes interrupted archive cleanup without touching login
  data.
- **Archived means inactive everywhere** — archived profiles are excluded from
  mouse mappings, global hotkeys, menu-bar icons, Open actions, and the normal App
  Profiles lists until restored.

Permanent deletion was deliberately not part of v1.2.1; missing data was reported and
never guessed at or recreated automatically.

## 1.2.0

This release brings together a major App Profiles personalisation upgrade and a
careful reliability pass across profile launching, recovery, Dock integration,
and post-update Accessibility guidance.

- **More App Profile icon options** — each generated profile can now carry its
  own icon. Open the new per-profile gear menu and choose **Change Icon** to
  replace it with your own PNG or ICO, tint the app's own icon in one of six
  colours, or add a coloured corner badge with the profile's initial (with a
  live preview), and reset to the app icon at any time. Custom icons survive
  data-folder recovery and appear consistently in both App Profiles and
  Mappings. The original app is never modified.
- **Tidier App Profile cards** — Rename, Change Icon, and Remove now live
  together behind the gear menu, and the everyday controls (Open, Assign, Menu
  Bar Icon) are grouped on one row, so long profile names have more room.
- **Fixed — menu-bar launch during a process race.** Launching or focusing a
  profile from its menu-bar icon no longer fails when the profile momentarily
  shows more than one process (an instance still starting, or an old one
  exiting); the check now settles and retries, and only genuinely persistent
  ambiguity is refused.
- **Fixed — relaunching a profile no longer opens a duplicate.** Launching a
  profile that is already running now reopens that instance's window and brings
  it to the front, instead of starting a second copy. This applies from every
  surface — the menu-bar icon, the Dock, Launchpad, and Finder. Previously this
  worked for apps that block their own duplicates (such as ChatGPT/Codex) but
  not for Claude, which allowed a new Claude to start on every relaunch. A closed
  window is reopened in the same running instance, so a relaunch never appears to
  do nothing. Existing profiles get the fix automatically: their launcher's
  runner is refreshed in place on the next launch, without touching the profile
  or its login.
- **More reliable Dock pinning and rename.** Klik PRO now recognises the Dock's
  percent-encoded launcher paths, avoiding a false “Dock icon was not added”
  message and keeping a pinned launcher's path and label in sync after rename.
  After changing a pinned profile's icon, macOS may retain the old Dock preview
  until that profile is clicked or the user next logs in; the menu bar,
  Launchpad, and Finder update immediately.
- **Clearer Accessibility re-grant after updates.** When Klik PRO Helper needs
  Accessibility permission again after an update — a case where macOS may still
  show it as enabled even though it must be re-granted — Klik PRO now explains
  the exact steps to remove and re-enable it, instead of leaving only the bare
  system prompt.

## 1.1.1

- **Advanced tab is lock-gated with a risk warning** — the Advanced tab now
  shows a lock in the tab bar while locked. The padlock on the tab is itself the
  control: clicking it opens a confirmation that spells out the risk (these
  options change where App Profile data is stored on disk; the wrong folder can
  leave profiles unfindable or split across locations) before the data-location
  options are revealed. Cancelling leaves everything locked.

## 1.1.0

- **Durable data folder (Advanced settings)** — a new, unlock-gated **Advanced**
  tab lets you choose a data folder where new App Profiles are stored so their
  logins survive uninstalling Klik PRO, and scan an existing folder to re-adopt
  the profiles it holds. On launch, if a previously configured data folder is
  located, its profiles are recovered automatically. Existing profiles are never
  moved; leaving the folder unset keeps the default behaviour unchanged.
- **Easier data-folder setup and recovery** — the data-folder picker can now
  create a new folder on the spot, and the recover-an-existing-folder flow makes
  clear you select the folder that contains `vault.json` (not the `~/.claude-*`
  or `~/.codex-*` links in your Home folder) and reveals hidden folders so they
  stay reachable.
- **Three-step onboarding** — first launch is now a guided flow: Welcome,
  Preferences (the four setting toggles on their own page), and an opt-in
  Accessibility step with **Set Up Accessibility…**, **Skip for Now**, and
  **Back**. Skipping still completes onboarding; the permission can be granted
  any time later from Settings.
- **About copyright** — the Settings About card now shows the project
  copyright line (© 2026 Aminudin Murad · GPL-3.0).
- **Fixed: phantom Duplicate badge** — a mouse button whose shortcut matched
  the stale keyboard combo of a button assigned to open a managed App Profile
  no longer shows a false Duplicate warning. The conflict checker now mirrors
  the runtime: a button that launches a profile owns no keyboard shortcut. A
  button whose target genuinely cannot launch still reports the conflict.

## 1.0.0 — Initial release

Klik PRO remaps the extra buttons on a "pro" mouse to recordable keyboard
shortcuts, and can generate isolated extra instances (App Profiles) of ChatGPT
or Claude, each with its own login.

- **Mouse shortcuts** — four recordable button shortcuts on the tested mouse
  (middle, Gesture, forward, back) with live conflict checking against
  duplicates, reserved macOS shortcuts, browser-extension commands, and combos
  already claimed system-wide. Gesture replaces the mouse's own `⌘Tab` output
  on supported device profiles without touching the physical keyboard's `⌘Tab`.
- **Thumb-wheel tab switching** — the horizontal wheel flips browser tabs, with
  per-browser combinations and a sensible fallback elsewhere.
- **App Profiles** — generate additional icons for ChatGPT or Claude, each with
  its own separate login and settings. The original app is never copied, cloned,
  renamed, or modified. Generated launchers open from Spotlight, the Dock, and the
  in-app Open button through one validated launch path; each profile can be
  renamed, pinned to the menu bar, assigned to a mouse button (from either the
  App Profiles tab or the Mappings list — the control shows the linked button
  with a chain-link indicator and changes on hover), or removed (profile data is
  retained for recovery). Profiles whose app uses a config home also expose a
  visible `~/.claude-*` / `~/.codex-*` link so multi-account tools detect them,
  without ever moving the profile's data. Existing compatible launchers are
  listed alongside generated ones.
- **Caffeinate** — an optional keep-awake menu on the Klik PRO menu-bar icon
  with 30-minute, 1-hour, 2-hour, and until-turned-off presets, powered by
  macOS's own `caffeinate`. A coffee-cup status icon appears while active, and
  the keep-awake can never outlive Klik PRO itself.
- **Menu-bar icon** — left-click opens Settings; right-click provides Settings,
  Caffeinate (optional), update check, About, and Quit, using native macOS
  menu placement. Two green dots show only while the input tap is active.
- **Boot behavior** — Launch at login starts only the background helper: no
  Settings window after a reboot, and the menu-bar icon appears reliably in
  the login session.
- **Onboarding** — a first-launch welcome guide walks through the required
  Accessibility approval with live status, a manual Recheck, and a guided
  reset flow.
- **Verified Terminal installer** — authenticates the release with a dedicated
  Ed25519 key, verifies checksums, bundle identities, universal architectures,
  and code-signature integrity before installing.
- **Native & lightweight** — Swift + AppKit/Carbon, universal Apple Silicon +
  Intel, macOS 13+, no dependencies or vendor drivers.

Known limitations: the app is ad-hoc signed (not notarized), so first launch
uses the documented Gatekeeper flow and macOS re-requests Accessibility after
in-place upgrades; removing an App Profile keeps its profile data by design.
