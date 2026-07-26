# Klik PRO — App Profile Compatibility

Apps that can run as isolated **App Profiles**, each holding its own login.

- **Verified** — Aminudin has manually declared that the app ships as Verified.
- **Unverified** — Aminudin has manually declared that the app ships as Unverified.
- **Pending** — not in Klik PRO yet. The method is known, but a rule pins the app's exact bundle
  identifier and Team ID, which can only be read from the app itself.

Only Verified and Unverified apps appear in Klik PRO, and only while the app is installed.
The badge is taken from this document; app versions and test evidence do not promote or demote it.

## Verified

| App | App |
|---|---|
| Antigravity | Gemini |
| Antigravity IDE | Google Chrome |
| Brave | Notion |
| Canva | Obsidian |
| ChatGPT / Codex | Slack |
| Claude | Spotify |
| Cursor | Visual Studio Code |
| Discord | Zoom |

## Unverified

None yet.

## Pending

Add a rule for any of these by supplying the app — installed or as a disk image is enough, it does
not need to run.

| App | App | App |
|---|---|---|
| Arc | Insomnia | Miro |
| Asana | Lens | MongoDB Compass |
| Chromium | Linear | Opera |
| ClickUp | Mattermost | Opera GX |
| Evernote | Microsoft Edge | Postman |
| Figma | | Signal |
| GitHub Desktop | | TablePlus |
| GitKraken | | Terminus |
| | | Todoist |
| | | Vivaldi |
| | | Windsurf |

Pending rows have no preassigned shipping badge. Engine type is planning context only; Aminudin
declares Verified or Unverified when an app moves into the shipping catalogue.

## Notes

- Install apps from the developer's own download, not the Mac App Store. App Store builds are
  sandboxed and cannot be isolated.
- **Spotify** runs one instance at a time — profiles switch rather than run side by side.
- **Cursor and Visual Studio Code** receive separate `--user-data-dir` and
  `--extensions-dir` paths inside each generated profile, isolating accounts, settings,
  workspace state, and extensions.
- Apps that hand sign-in to your default browser may return the login to the original app instead of
  the profile. Quit the original app during a profile's first sign-in.

## Maintaining this list

This document is the sole product authority for the shipping catalogue and badge. Change an app's
status here only by owner decision, then mirror the declaration in the compiled registry. The
registry still pins bundle identifier, Team ID, engine, and isolation recipe as security gates.
Automated tests enforce exact document/registry parity; they never promote or demote an app.
