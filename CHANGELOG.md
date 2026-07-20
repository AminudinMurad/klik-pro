# Changelog

All notable changes to Klik PRO are documented here.

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
