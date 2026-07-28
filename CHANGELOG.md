# Changelog

All notable changes to Klik PRO are documented here.

## 1.5.1 (unreleased)

- Added an Xcode development bridge for selecting the full Xcode toolchain,
  opening the source, and recording repeatable Instruments traces without
  replacing the checked-in release build.
- Removed unchanged-state full code-signature rescans from the helper's
  five-second availability poll. Full validation still runs at startup, after
  relevant profile files change, and before every managed launch.
- Reduced the dashboard to a 940×770-point complete window that fits 13-inch
  MacBook displays without an outer vertical scrollbar. Native Apps, App
  Profiles, and Advanced maintenance retain independent scrolling inside their
  list panels.

## 1.5.0

The app lists on Mappings and App Profiles now use one card, and a fresh install starts quiet.

- **One card everywhere.** All four app lists — Native Apps and App Profiles on Mappings,
  the generator and your profiles on App Profiles — now use the same two-row card: a large
  app icon down the left, the name on the first row, and the buttons lined up on the second.
  The columns line up across both tabs.
- **Per-card "Native app" label removed.** The list is already titled Native Apps, so
  repeating it under every name only cost a row.
- **Verified / Unverified badge.** Each app in the catalogue now shows how far Klik PRO has
  tested it, beside its name. Your own profiles carry no badge — they inherit their app's.
- **Menu Bar Icon moved into the gear.** It was a switch sitting in the middle of every
  profile card; it is now the last item in that card's gear menu, still a real switch. The
  name gets the whole row back. Mappings rows gained a gear for the same reason.
- **Refresh moved into each list's heading.** One small refresh arrow now sits at the right
  of every list's title instead of floating above the columns, so whichever list you are
  reading has it to hand. It also now visibly responds while a rescan runs — previously a
  refresh from the Mappings tab did rescan, but nothing on screen acknowledged it.
- **Pin the three apps you actually use.** Every card now has a pin beside its gear. Pinned
  cards move to the top of the list, on both tabs, and the Mappings lists show exactly three
  cards at a time — so your three pinned apps are the three you see without scrolling. Each
  list keeps its own three pins: three native apps and three App Profiles.
  - Nothing is pinned by default, and Klik PRO never pins anything for you. Until you pin
    something the lists stay in their usual order.
  - Once three are pinned, a fourth pin is refused rather than quietly pushing one out —
    unpin one to free the slot. The pin on an unpinned card dims and says so when the list
    is full.
  - A pin for an app you have since uninstalled (or a profile you deleted) does not hold a
    slot, so you can never end up unable to pin anything with no pinned card left on screen
    to unpin. Reinstalling the app brings its pin back.
  - Pinning only reorders. Nothing is hidden: everything past the third card is one scroll
    away, and an app with a mouse button assigned to it stays in the list whether or not
    it is pinned.
  - Your pins are remembered between launches, and pinning does not count as an unsaved
    change — it never lights up "Unsaved changes" or asks you to Save first.
- **Scroll bars are honest again.** In the app lists and App Profile Maintenance the scroll
  handle was almost full height however long the list was, so it barely moved. It is now
  sized to how much is actually off-screen.
- **A fresh install starts quiet.** Middle button, Gesture button and the horizontal thumb
  wheel all arrive off, and every thumb-wheel browser checkbox is off. Only Forward and Back
  arrive mapped, to browser Back/Forward. No mouse button is pre-assigned to an app.
  Existing setups keep their current mappings.
- **No shortcut is suggested where you never chose one.** Middle, Gesture and the three app
  hotkeys now arrive with *no* shortcut at all rather than a pre-filled one, and read
  **No shortcut**. Only Forward and Back arrive mapped — beyond the scroll wheel, the two side
  buttons are the pair essentially every advanced mouse has, so they are the only controls
  Klik PRO assumes exist.
  - Those rows hide their Reset arrow, since there is no default to go back to, and show no
    conflict badge, since a shortcut that does not exist cannot clash with anything.
  - On a row where you *have* recorded a shortcut, the Reset arrow now clears it back to
    empty. Previously it reset to a combo nobody picked, and there was no way back to blank.
  - This also removes a collision the old defaults carried, where ChatGPT and Gemini were both
    pre-filled with ⌃⌥⌘G.
  - Existing setups keep every shortcut they have.
- **Fixed: long app names truncated early.** Names such as "ChatGPT / Codex" were cut short
  with empty space still next to them.
- **Assign is no longer offered where it cannot work.** Canva, Zoom and Spotify have nowhere
  to store a mouse-button assignment yet, so the button is disabled and says why instead of
  doing nothing when pressed.

## 1.4.6

Gemini joins App Profiles — the first supported app that is not built on Electron.

- **Gemini App Profiles.** Google's Gemini desktop app can now hold a separate profile
  per Google account, each with its own login, cookies, notebooks and chat list, all
  running at the same time. Verified with four accounts open together.
- **Listed as Experimental.** Isolation and login persistence are confirmed on-machine,
  but the profile has not yet been re-checked after a Gemini update — the second gate
  Klik PRO requires before calling an app Verified.
- **Gemini logins persist.** Gemini stores its sign-in somewhere only reachable when it
  can also see the login keychain; without that it signed in, worked for the session,
  then silently forgot the account on quit. Profiles are now set up so it stores the
  sign-in properly the first time.
- **No change to the app itself.** Gemini accepts no profile switch on launch, so Klik
  PRO redirects its storage location per profile instead. `/Applications/Gemini.app` is
  never copied, modified or re-signed, and profiles survive Gemini's own updates.
- **Fixed: profiles were built with launch options their app did not support.** The
  Electron-style data-folder switch was applied unconditionally. Profiles now receive
  only the options their app understands.

Two profiles on the *same* Google account show the same conversations — Gemini keeps
chats on Google's servers. App Profiles separate logins, not cloud history.

## 1.4.5

A fix for App Profile data that could not be deleted, and a clearer Advanced tab.

- **Delete Data works again** — deleting an App Profile's login data, or leftover data
  with no profile, failed for every ChatGPT or Claude profile that had been launched.
  Chromium writes four links of its own into a profile the first time it runs, and the
  ownership check refused any profile containing a link. Move to Trash and Delete
  Permanently both complete now, and Deep Scan for Leftovers can clean the data
  folders it finds.
- **A failure message that is true** — a refused removal used to advise quitting the
  app or restarting macOS, which could never help. It now says whether Klik PRO could
  not verify the item as its own or the disk refused.
- **A data folder from the first launch** — onboarding gains a second step offering
  `~/Klik PRO Vault` as its default action, so a fresh install can store profile logins
  somewhere that survives an uninstall instead of moving them later. Choose a different
  folder on the page, or Skip for Now to keep them in Application Support.
- **Scan & Import** — "Scan & Adopt" is renamed and moves up beside the data-folder
  controls it belongs with.
- **Profile Cleanup** — Deep Scan for Leftovers moves into its own section below App
  Profile Maintenance.

Nothing outside a profile is removed: a link pointing at a folder outside the profile
still fails closed, and a profile's own links travel to the Trash as links.

## 1.4.4

A visual redesign of the Mappings tab, plus the Horizontal Thumb Wheel's browser
control brought into the tab.

- **Mouse Profile card** — the mouse and its four button callouts now sit together
  in one bordered "Mouse Profile" panel, separated from the app lists, with each
  callout beside the button it controls.
- **Compact, stacked button controls** — each mouse button's action picker and its
  shortcut or app picker are stacked and sized to their content, arranged around
  the mouse.
- **Horizontal Thumb Wheel in Mappings** — the thumb wheel appears as its own
  control with a browser selector, kept two-way in sync with the browser checkboxes
  in Settings.
- **Refresh App List** — the rescan control gains a refresh icon and sits above the
  Native Apps and App Profiles lists.

Existing button assignments and shortcuts are unchanged; this release reorganizes
how the Mappings tab presents them.

## 1.4.3

A refinement of how the App Profile generator manages the native app's Dock icon.

- **Smarter Dock icon on generation** — creating an App Profile no longer forces a
  Klik PRO Dock launcher when a working Dock entry for the native app already exists.
  If either the native app's own Dock tile or Klik PRO's launcher is already present,
  the step is skipped and the "always on" row is no longer shown; the launcher is
  added only when neither is present, so you always keep a way to reopen the native app.
- **Add Native App Dock Icon** — the generator card's gear menu gains this counterpart
  to Remove Native App Dock Icon, so the native app's own Dock tile can be put back
  at any time.
- **Generator card reflects your changes** — after Rename Dock Icon or Change Icon,
  the generator card tile updates to show the new name and custom icon, matching the
  Dock launcher; Reset returns it to the native app's own name and icon.
- **Reliable Dock icons when both are added at once** — creating a profile that adds
  both its own Dock icon and the native launcher in one step now lands both reliably,
  where the profile's tile could previously be dropped during the Dock relaunch.
- **Add to Dock for a profile** — each App Profile's gear menu gains **Add to Dock**,
  so a profile's icon can be pinned to the Dock at any time.

## 1.4.2

Generator-card parity with the per-profile controls for the native Klik PRO Dock launcher.

- **Rename Dock Icon… and Change Icon… on the generator card** — the generator card's
  gear menu acts on the native app's Klik PRO Dock launcher. Rename updates the Dock
  tile label; Change Icon supports tint, badge, a custom PNG/ICO image, and reset —
  the same options already available on each managed profile.
- **Durable name and icon** — a personalized launcher's custom name and icon survive
  an App Profile generation and a gear **Replace**, so it keeps its identity across
  rebuilds.

## 1.4.1

A small front-of-app polish release.

- **Aligned tab bar** — the tab bar gains a subtle border and sits on the header's
  centerline, aligned with the Klik PRO wordmark and the updates button; labels and
  the Advanced lock glyph are vertically centered from measured text metrics.
- **Compact updates control** — the header's Check for Updates button becomes a
  compact **↻ Updates…** control, still top-right and still reading **Update available**
  when a newer version is found.
- **Consistent "native" wording** — the built-in ChatGPT and Claude apps are now
  labelled "native" throughout (for example, "ChatGPT / Codex (native)").

## 1.4.0

A refresh of the main window navigation and the Mappings screen.

- **Pill-shaped tab bar** — the active tab is a filled-blue pill, tabs are evenly
  spaced, and the row is centered in the header beside the logo. Tab order is
  Mappings, App Profiles, Settings, Advanced.
- **Tightened Check for Updates** button to sit cleanly within the new header layout.
- **First-scan spinner** — the Mappings **Native Apps** card shows a loading spinner
  during the first-launch app scan instead of flashing "No native apps installed".
- **Accurate card sizing** — Mappings cards auto-hide their scrollers and size content
  accurately, so a fitting group shows no stub handle and an overflowing list gets a
  proportional one.
- **Thumb Wheel Tab Switching moved to Settings**, grouping it with the app's other
  preferences. Tab indices and hit-testing are unchanged.

## 1.3.2

A focused original-app relaunch fix and App Profiles layout update.

- **Original apps reopen independently** — when a ChatGPT or Claude App Profile is
  still running, Klik PRO now identifies the true original process instead of letting
  macOS redirect the Open action to the profile. If the original is closed, Klik PRO
  starts a new original instance; if it is already running, Klik PRO reopens that
  exact process.
- **App Profile duplicate protection remains intact** — forced original-app launches
  are isolated from managed-profile routing. Existing profiles are still matched by
  their exact data directory and reopened by verified PID rather than duplicated.
- **Open from the generator** — installed ChatGPT and Claude cards now provide an
  **Open** action immediately before **+ New Profile**.
- **Balanced App Profiles layout** — the generator and profile-list columns now use
  equal widths, and each profile's **Menu Bar Icon** toggle sits directly left of its
  settings gear.
- **Numbered, customisable badges** — Badge mode defaults to the first unused number
  for that app (`1`, then `2`, and so on), remembers applied badge characters, and
  still lets the user replace the default with any single character in the live preview.
- **Full-size badged Dock and Launchpad icons** — badge composition stays inside the
  source app icon's native safe area, preventing macOS from shrinking the whole icon
  into a second inset squircle while retaining the badge's displayed size.
- **Full-size PNG Dock and Launchpad icons** — chosen PNG/ICO artwork now uses the
  native macOS app-icon footprint instead of touching the ICNS canvas edges and
  triggering an additional system scale-down.
- **Expanded Tint and Badge palette** — Yellow, White (`#FFFFFF`), and Black
  (`#000000`) join the existing six colours. Light badges automatically use dark
  lettering and rings so their character remains legible.
- **Visible image requirements** — Image mode now states its minimum accepted PNG/ICO
  resolution before selection: the shortest side must be at least 256 pixels.

## 1.3.1

A focused assignment-linking fix for original apps and generated App Profiles.

- **Original apps in Mappings** — the Open App selector now includes the installed
  ChatGPT / Codex and Claude apps alongside generated App Profiles.
- **Both tabs stay linked** — assignments made from Mappings immediately update App
  Profiles, and assignments made from App Profiles immediately update Mappings.
- **One cross-checked owner** — both tabs use the same ownership, conflict, move,
  Force Release, and clear logic, so one physical button cannot drift between targets.

## 1.3.0

Original ChatGPT and Claude apps join the App Profiles assignment experience without
becoming managed profiles.

- **Original apps are assignable** — each installed app generator card now offers
  **+ New Profile** and **Assign Button** as separate actions.
- **One ownership model** — a physical mouse button belongs to exactly one original
  app or generated profile; reassignment uses the existing Force Release confirmation.
- **Mappings includes originals** — installed original apps appear with only **Open**
  and **Assign Button**, never Rename, Repair, Archive, Change Icon, or data removal.
- **No Special Feature ghost state** — original-app mouse assignments remain normal
  launch actions when the legacy Special Feature toggle changes; its dormant shortcut
  cannot reappear as a duplicate conflict.
- **Direct original-app launching** — original assignments open the installed ChatGPT
  or Claude app directly and no longer depend on a legacy launcher wrapper.
- **Clear from the same dialog** — **None — Clear assignment** restores a button's
  normal mapping without returning to the legacy Special Feature controls.
- **Full-size custom icons** — transparent padding embedded inside PNG/ICO artwork and
  source-app icons is removed before rendering, so plain, tinted, and badged icons fill
  the macOS squircle instead of appearing as a smaller icon inside it.

## 1.2.9

A focused Deep Scan correction for previously used durable Data Folders.

- **Previously used Data Folders remain discoverable** — clearing the active Data
  Folder keeps its validated path in a bounded scan allow-list; older configurations
  can select the previous folder through a read-only picker.
- **Markerless folders stay manual-review-only** — UUID-named folders without Klik
  PRO ownership markers are reported instead of producing a false clean result, but
  remain completely outside Move to Trash and Delete Permanently flows.
- **Reveal in Finder is visible** — manual-review results can be revealed from both
  the scan summary and App Profile Maintenance for safe inspection and manual cleanup.

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
