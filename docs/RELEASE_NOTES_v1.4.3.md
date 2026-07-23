# Klik PRO 1.4.3

Klik PRO 1.4.3 refines how the App Profile generator manages the native app's
Dock icon, and keeps the generator card in sync with your customizations.

- **Smarter Dock icon on generation.** Creating an App Profile no longer forces a
  Klik PRO Dock launcher when you already have a working Dock entry for the native
  app — if either the native app's own Dock tile or Klik PRO's launcher is already
  in the Dock, the step is skipped and the "always on" row is no longer shown. The
  launcher is added automatically only when neither is present, so you always keep
  a way to reopen the native app.
- **Add Native App Dock Icon.** The generator card's gear menu gains **Add Native
  App Dock Icon**, the counterpart to Remove Native App Dock Icon, so you can put
  the native app's own Dock tile back at any time.
- **Generator card reflects your changes.** After Rename Dock Icon or Change Icon,
  the generator card tile now updates to show the new name and custom icon, matching
  the Dock launcher. Reset returns the tile to the native app's own name and icon.

Because the Dock and LaunchServices cache icons and labels, a change may take a
moment — or a relaunch — to appear on the tile.

No other App Profile behavior changes in this release.
