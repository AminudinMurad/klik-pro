# Klik PRO 1.3.1

Klik PRO 1.3.1 fixes mouse-button assignment consistency across the Mappings and
App Profiles tabs.

- The Mappings tab's **Open App** selector now includes the installed original
  **ChatGPT / Codex** and **Claude** apps alongside generated App Profiles.
- Assigning, moving, or clearing a button from either tab immediately updates the
  other tab.
- Original apps and generated profiles share one ownership and conflict check, so
  each physical mouse button has exactly one launch target.

This release keeps the App Profile lifecycle unchanged: original apps remain normal
installed applications and are never treated as generated or managed profiles.
