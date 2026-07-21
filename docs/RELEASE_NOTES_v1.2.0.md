# Klik PRO 1.2.0 (build 4)

Klik PRO 1.2.0 is a substantial App Profiles quality release, shaped by extensive
testing and refinement across the complete launch, management, and recovery workflow.
Profiles are easier to recognise, more consistent across the app, and more reliable
when opened repeatedly from different parts of macOS.

![Klik PRO 1.2.0 App Profiles icon customisation](https://raw.githubusercontent.com/AminudinMurad/klik-pro/v1.2.0/assets/app-profiles-icon-showcase.gif)

## Highlights

- **Give every App Profile its own identity.** Use a custom PNG or ICO, tint the
  original app icon with one of six colours, or add a coloured initial badge with a
  live preview. Resetting restores the source app icon, and the original app is never
  modified.
- **See the same icon everywhere that matters.** App Profiles and Mappings refresh
  together immediately, while generated launchers carry the icon into the menu bar,
  Launchpad, and Finder. Custom icons also survive durable-folder recovery.
- **Cleaner profile cards.** Rename, Change Icon, and Remove now share one gear menu,
  leaving Open, mouse-button assignment, and Menu Bar Icon as the everyday controls.
- **One profile, one running instance.** Reopening an already-running profile now
  restores and focuses its existing window instead of starting a duplicate. The fix
  applies whether the profile is opened from Klik PRO, its menu-bar icon, the Dock,
  Launchpad, or Finder, and older generated launchers heal in place when next used.

## Reliability fixes

- Menu-bar launches now settle and retry through short-lived process races rather than
  failing while an instance is starting or an old process is exiting.
- Dock matching now understands percent-encoded launcher paths, preventing false
  “Dock icon was not added” messages and keeping renamed pinned launchers in sync.
- Accessibility recovery after an update now explains how to remove and re-enable
  Klik PRO Helper when macOS displays a stale permission state.

## Important Dock behaviour

macOS may keep showing its cached old preview for a pinned Dock tile after that
profile's icon changes. The tile corrects itself when clicked or after the next login.
The App Profiles tab, Mappings tab, menu bar, Launchpad, and Finder update immediately.
Klik PRO does not request Accessibility control of the Dock or steal focus merely to
force this cosmetic refresh.

## Upgrade

Download the universal macOS DMG (recommended) or ZIP. Existing settings, App Profile
logins, durable data folders, assignments, and generated launchers are preserved. As
with earlier ad-hoc-signed builds, macOS may require Accessibility permission for
**Klik PRO Helper.app** to be granted again after replacement; follow the guidance in
Settings if the input status is not **Granted**.

See the complete history in [CHANGELOG.md](../CHANGELOG.md) and installation or
repair guidance in [INSTALL.md](INSTALL.md).
