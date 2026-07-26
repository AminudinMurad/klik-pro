# Klik PRO — App Profile Compatibility

Apps that can run as isolated **App Profiles**, each holding its own login.

- **Verified** — a rule ships in Klik PRO and the isolation method is proven.
- **Unverified** — a rule ships, the method is plausible but not yet proven.
- **Pending** — not in Klik PRO yet. The method is known, but a rule pins the app's exact bundle
  identifier and Team ID, which can only be read from the app itself.

Only Verified and Unverified apps appear in Klik PRO, and only while the app is installed.

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

TablePlus would land in **Unverified** — it is a native app, where the isolation method is less
predictable. Everything else here is Electron or Chromium and would land in **Verified**.

## Notes

- Install apps from the developer's own download, not the Mac App Store. App Store builds are
  sandboxed and cannot be isolated.
- **Spotify** runs one instance at a time — profiles switch rather than run side by side.
- Apps that hand sign-in to your default browser may return the login to the original app instead of
  the profile. Quit the original app during a profile's first sign-in.

## Maintaining this list

An app moves from Pending once its bundle identifier, Team ID and engine have been read and a rule
added. It moves to Verified once two profiles have been signed into different accounts and confirmed
independent.
