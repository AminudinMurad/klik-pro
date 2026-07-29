# Klik PRO v1.5.4

Klik PRO 1.5.4 corrects the five-card Mouse Mappings dashboard introduced in
v1.5.3, restoring its visual depth and clearing up misleading or cramped states.

## Changes

- Forward and Back now use the same **Shortcut** action-menu label as Middle
  and Gesture.
- Their **Browser →** and **Browser ←** keyboard-shortcut values now fit fully
  beside their reset controls.
- Horizontal Thumb Wheel no longer displays an **OK** badge because its browser
  selection has no shortcut-conflict state to validate.
- Each mapping's saved colour now appears as a subtle carousel wash, with
  gradients, highlights, and restrained shadows restoring separation between
  the slide and its five control cards.
- Reset controls and the optional **Open App** action remain available.
- Mouse routing, configuration schema, responsive sizes, and the v1.6
  mouse-independent profile boundary are unchanged.

## Release metadata

- Version: **1.5.4**
- Build: **27**
- Minimum macOS: **13.0**
- Architectures: **Apple Silicon and Intel**

## Verification

- The full source, routing, helper, App Profile, hit-test, and deterministic
  preview gate passed.
- Two independent preview runs matched byte for byte.
- Dedicated shortcut-mode previews confirmed that Forward and Back show
  **Shortcut** beside complete Browser arrow values, the thumb-wheel badge is
  absent, and mapping-specific slide washes render consistently.
