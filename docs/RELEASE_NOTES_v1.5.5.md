# Klik PRO v1.5.5

Klik PRO 1.5.5 hardens the authenticated installation path after a live
installation was found with current version metadata but an earlier main
executable.

## Changes

- The verified Terminal installer now requires the staged main app and helper
  executables to match the authenticated DMG byte for byte.
- The same exact-identity check runs again after the app is activated in
  `/Applications`, before the temporary rollback copy is discarded.
- Any mismatch fails closed and preserves the existing rollback behavior.
- The corrected Mouse Mappings dashboard remains unchanged: Horizontal Thumb
  Wheel has no misleading **OK** badge, Browser arrow values fit, and the
  mapping slide retains its colour wash and card depth.
- Mouse routing, configuration schema, responsive sizes, App Profiles, and the
  v1.6 mouse-independent profile boundary are unchanged.

## Release metadata

- Version: **1.5.5**
- Build: **28**
- Minimum macOS: **13.0**
- Architectures: **Apple Silicon and Intel**

## Verification

- The full source, routing, helper, App Profile, hit-test, deterministic preview,
  installer-integrity, and universal-package gates passed.
- Two independent preview runs matched byte for byte.
- The authenticated v1.5.5 package passed a real upgrade with unchanged
  configuration, exact installed executable identity, a valid running helper,
  and live dashboard inspection.
- As expected for a newly signed helper build, macOS requires its Accessibility
  grant to be enabled again before physical button mappings resume.
