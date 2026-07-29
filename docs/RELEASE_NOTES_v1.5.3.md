# Klik PRO v1.5.3

Klik PRO 1.5.3 makes the responsive dashboard denser, clearer, and faster to
scan on a smaller MacBook without changing mouse-profile routing. The complete
release remains freely resizable from 940×770 to 1280×960 points.

## Highlights

- **Five-card Mouse Mappings workspace.** Middle, Back, Forward, and Gesture
  controls now surround the centred mouse, with Horizontal Thumb Wheel in a
  matching top-centre card. Every card keeps one aligned action/value/reset row.
- **More room for mappings and app lists.** Moving persistent actions out of the
  old footer gives Mouse Mappings more vertical breathing room at the unchanged
  13-inch minimum.
- **Compact header actions.** A disk Save action now sits with Close and Power
  Off. Close protects staged edits with Save, Discard, and Cancel; Power Off
  separately confirms before stopping Klik PRO and turning off Launch at login.
- **Focused Settings cards.** Updates now lives in About. Accessibility status
  and Open Settings, Recheck, Reset, and Logs are grouped into one compact card.
- **Visual Best Fit tiles.** The five existing resize presets now appear as
  MacBook tiles with exact frame dimensions, a clear green active state,
  keyboard-accessible radio semantics, and concise resize guidance.
- **v1.6 remains separate.** This release does not add sender-aware mouse routing
  or mouse-independent profiles.

## Release metadata

- Version: **1.5.3**
- Build: **26**
- Minimum macOS: **13.0**
- Architectures: **Apple Silicon and Intel**

## Quality checks

- The complete automated source, routing, helper, App Profile, UI, and packaging
  gate passed on both supported architectures.
- Two independent Retina preview runs matched byte for byte across the responsive
  dashboard matrix.
- Live isolated AppKit testing covered the five Best Fit radio controls, keyboard
  and click resizing, Close and Power Off confirmations, and
  Save → Close → relaunch persistence.
- The universal DMG and ZIP include signed SHA-256 manifests. The authenticated
  installer verifies the release key, version, architectures, and code-signature
  integrity before replacing an existing installation.
