# Klik PRO v1.5.0

Klik PRO 1.5.0 removes the old App Profiles ceiling: it is no longer limited to ChatGPT / Codex and Claude. Supported installed apps now appear from a broader catalogue, with clearer app cards, compatibility badges, and actions that reflect what each app can actually do.

This release also makes mouse mappings feel stable, deliberate, and easier to trust with a new three-preset workflow: set up different button layouts, save them explicitly, and activate only the one you want live.

## Main Improvement

- **App Profiles beyond ChatGPT and Claude.** The supported catalogue now includes ChatGPT / Codex, Claude, Gemini, Canva, Zoom, Spotify, Antigravity, Antigravity IDE, Google Chrome, Brave, Cursor, Discord, Notion, Obsidian, Slack, and Visual Studio Code.
- **Installed-app cards with compatibility badges.** Klik PRO shows installed supported apps from the catalogue, labels their support level, and keeps unsupported apps out of the workflow.
- **Three saved mapping presets.** Keep up to three independent mouse-mapping profiles, each with its own button toggles, keyboard shortcuts, Open App targets, browser selections, and colour.
- **Clear Save and Activate behavior.** Editing a slide no longer feels like it is secretly changing the live helper state. **Save** stores the preset; **Activate** makes that preset the active mapping.
- **Cleaner defaults for new installs and resets.** Fresh/reset presets now start quieter: Forward and Back keep browser-history mappings, while Middle, Gesture, thumb-wheel switching, browser checkboxes, and app assignments start off.

## What Changed

- **Preset colours.** The three reset presets now use Pearl White, Mist Blue, and Rose.
- **Smoother navigation.** Moving between mapping slides is faster and more predictable.
- **Better mapping layout.** The Mappings view is more compact, with clearer spacing around the mouse callout and three visible profile slides.
- **Browser selector checkboxes.** Browser choices are now easier to scan and adjust.
- **Shortcut behavior tightened.** Rows with no chosen shortcut now show **No shortcut** instead of carrying a suggested combo, and reset clears them back to blank.
- **App list polish.** Native Apps and App Profiles use a cleaner card layout, with refresh controls in each list heading, pinning for the three apps you use most, and improved scroll bars.
- **Per-app assignment clarity.** Apps that do not support mouse-button assignment yet explain that directly instead of showing a dead action.

## Fixes

- Long app names such as "ChatGPT / Codex" no longer truncate too early.
- Canva, Zoom, and Spotify no longer show an active Assign action where mouse-button assignment is not supported yet.
- New installs no longer pre-fill unused app hotkeys or create shortcut conflicts by default.

## Build

- Version: **1.5.0**
- Build: **23**
- Distribution: universal macOS DMG and ZIP for Apple silicon and Intel
