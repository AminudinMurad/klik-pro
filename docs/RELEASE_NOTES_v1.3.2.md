# Klik PRO 1.3.2

Klik PRO 1.3.2 contains nine focused improvements to original-app launching and the
App Profiles screen.

- Original ChatGPT and Claude can now be reopened while any of their generated App
  Profiles remain running. Klik PRO distinguishes the true original process from
  profiles that share the same vendor executable and application identity.
- Managed App Profiles retain their duplicate-safe behavior: an existing profile is
  reopened by its verified process ID, and a second instance is not created.
- Installed-app generator cards now include **Open** immediately before
  **+ New Profile**.
- The generator and profile-list columns are equal width, with each profile's
  **Menu Bar Icon** toggle positioned directly left of its settings gear.
- Badge mode defaults to the first unused number for that app (`1`, then `2`, and so
  on), remembers applied badge characters, and lets the user replace the suggested
  number with any single character in the live preview.
- Badged profile icons now retain the source app's full native size in Dock and
  Launchpad instead of appearing inside a second inset squircle. Menu-bar rendering
  remains unchanged.
- Custom PNG/ICO profile icons now use the native macOS icon footprint, preventing
  Dock and Launchpad from adding the same extra inset normalization.
- Tint and Badge now offer nine colours, adding Yellow, exact White (`#FFFFFF`), and
  exact Black (`#000000`). Light badges use automatic dark contrast for readability.
- Image mode now shows the minimum accepted PNG/ICO resolution before file selection:
  the image's shortest side must be at least 256 pixels.

The original-app relaunch correction applies equally to ChatGPT and Claude.
