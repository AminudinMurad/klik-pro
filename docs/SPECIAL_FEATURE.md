# Special Feature — ChatGPT / Codex & Claude Quick Launch

> This describes the hardcoded Quick Launch feature for pre-existing external
> launcher wrappers. For generating a second isolated instance of ChatGPT or
> Claude directly from Klik PRO, see the **App Profiles** tab and
> [`APP_PROFILES.md`](APP_PROFILES.md).

> **Heads up:** this feature is the one part of Klik PRO that is *not*
> portable out of the box. It depends on a specific dual-instance launcher
> setup on the user's machine. Its master toggle is enabled only when the real
> ChatGPT or Claude desktop app is installed; with neither installed it stays OFF and
> disabled. After that gate, turning it ON only shows and enables a launcher side when
> both its desktop app and wrapper exist. Any mouse button
> assigned to a missing wrapper simply uses
> its preserved normal action instead. Actual button and wheel support still varies
> by mouse hardware.
> Klik PRO's own persistent menu-bar icon is also independent of this toggle.

## What the card does

The **Special Feature** card has one master ON/OFF toggle plus independent controls
for ChatGPT / Codex and Claude. The master toggle becomes interactive when Klik PRO
validates either real desktop app at its standard `/Applications` path; a leftover
wrapper by itself does not enable it. Each app-specific picker and hotkey reports
**Not installed** or **Launcher missing**. Its hotkey and new picker choices stay
non-interactive until that side is runnable; if an old picker assignment exists, the
dropdown remains available only so **None** can clear it.

1. **Optionally shows the launcher menu-bar icon(s)** — one for ChatGPT / Codex, one
   for Claude — that launch a second instance of the app when clicked. The Settings
   tab can hide both icons without stopping the background helper.
2. **Registers the launch hotkey(s)** — default `⌃⌥⌘G` for ChatGPT / Codex,
   `⌃⌥⌘C` for Claude.
3. **Optionally links each launcher to a mouse button** — each **Mouse Button**
   dropdown offers **None**, **Middle**, **Gesture**, **Forward**, and **Back**.

While OFF, those launcher icons are hidden and the hotkeys are released system-wide so
other apps can use those combos. While ON, **Show Special Feature icons** can hide only
the icons while the hotkeys and assigned mouse buttons remain active. The hotkeys have no individual on/off switch
— the single master toggle governs the whole feature — and each recorder stays
editable while its desktop app and launcher are ready. The dedicated Klik PRO icon
has its own separate visibility setting and registers no keyboard shortcut.

The two launchers cannot claim the same physical button. When a button is linked, its
visible combo mirrors the corresponding launcher hotkey automatically, so changing that
hotkey keeps the
button in sync. Its normal Recordable Shortcuts mapping is preserved underneath.

With Special Feature ON and the matching launcher wrapper runnable, pressing the linked
button launches that app directly. Turning Special Feature OFF, choosing **None**, or
removing the matching wrapper restores the preserved normal button action. This applies
equally to Middle, Gesture, Forward, and Back.

### Works with one app or both

You don't need both apps installed. Klik PRO first checks which real desktop app is
installed, then requires that app's launcher wrapper before enabling its launch side:
with just ChatGPT / Codex set up you get its launcher side and `⌃⌥⌘G` alone; with just
Claude, only its launcher side and `⌃⌥⌘C`. Visible icons follow the separate Settings
preference. This covers the
common case of wanting two instances of a single app. A mouse assignment on the
unavailable side falls back to its preserved normal action. If an app or wrapper is
added or removed while Klik PRO is open, the controls refresh and the combined
background helper restarts as needed; installing an app never turns the feature ON by
itself.

## The dual-instance idea

"Launch ChatGPT / Codex or Claude" here does **not** mean the normal app window. It
launches (or focuses) a **second, independent instance** of each app running
under its own profile, so a personal window and a separate work/Codex window
can run side by side.

This is done with per-app wrapper "launcher" apps that Klik PRO calls by
path (see `Sources/KlikProConfig.swift`):

```
~/Library/Application Support/ChatGPT Launchers/ChatGPT.app
~/Library/Application Support/Claude Launchers/Claude.app
```

Each launcher is a tiny `.app` wrapping a shell script that:

- **Focuses** the target instance if it's already running, otherwise
- **Opens** `/Applications/ChatGPT.app` (or `Claude.app`) with a dedicated
  `--user-data-dir` profile so it comes up as a distinct instance rather
  than focusing the one you already have open.

For ChatGPT / Codex specifically, the launcher also sets a separate
`CODEX_HOME` and Codex user-data path. The current ChatGPT desktop app
installs Codex — the `~/.codex` home — so the second instance gets its own
Codex state too. There is no separate "Codex app" to install; Codex ships
with the ChatGPT desktop app, and the launcher just points a second instance
at a different profile.

## What you need to replicate it

1. `/Applications/ChatGPT.app` and/or `/Applications/Claude.app` installed —
   one is enough.
2. The matching launcher wrapper app present at the path above. Each one just
   needs to open its target app with a distinct `--user-data-dir` (plus the
   Codex env vars for ChatGPT / Codex) and, ideally, focus the instance if
   it's already running. Klik PRO enables only a side whose app and launcher both
   validate as runnable application bundles.
3. The menu-bar icons use the installed apps' own icons from these required standard
   locations:
   ```
   /Applications/ChatGPT.app
   /Applications/Claude.app
   ```

If you don't use ChatGPT / Codex or Claude, or don't want a dual-instance
setup, just leave this toggle OFF — the rest of the app doesn't depend on any
of it, and any assigned mouse buttons use their preserved normal actions.

## Adapting it to launch your own apps

The target paths, expected bundle identifiers, and wrapper paths are defined in
`Sources/KlikProConfig.swift`; `MenuBarController` in `Sources/KlikProInput.swift`
builds the matching launcher items. To adapt the feature, change those values and use
runnable `.app` bundles for both the main targets and their wrappers. Plain script paths
do not pass the runtime checks. With matching code changes, the feature can be
repurposed as a generic "two-app quick launch + two menu-bar buttons" toggle.
