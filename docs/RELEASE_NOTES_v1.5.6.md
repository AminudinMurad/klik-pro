# Klik PRO v1.5.6

Klik PRO 1.5.6 keeps the dashboard compact and predictable on every supported
MacBook by making responsiveness vertical-only.

## Changes

- Every MacBook preset now uses the proven 940-point dashboard width.
- Dashboard Height offers five model-based outer frames: 940×770 for 13-inch M1,
  940×820 for 13-inch M2+, 940×860 for 14-inch, 940×900 for 15-inch, and 940×960
  for 16-inch.
- Manual resizing is restricted horizontally while remaining continuous between
  the supported minimum and maximum heights.
- Settings now uses Dashboard Height wording and reports non-preset heights as
  Custom height.
- The Horizontal Thumb Wheel callout on Mappings is moved upward and reduced to
  its toggle, title, and a compact globe menu for quickly enabling browsers; the
  full browser choices remain available in Settings.
- The mouse artwork is centred horizontally and vertically within the mapping
  slider, and the four surrounding cards move upward into a vertically centred
  group with the callout geometry following the new positions. The thumb-wheel
  card connects to its target with a clean straight line.
- Mapping-slide dots now surround the current profile name according to sequence:
  two on the right for the first slide, one on each side for the second, and two
  on the left for the third.
- Dashboard Height cards no longer flash a blue native radio-button circle when
  pressed; their custom green selection and accessible radio behavior remain.
- A previously saved wider frame is normalized to 940 points while preserving
  its valid height and approximate horizontal centre.
- Mouse routing, saved configuration, App Profiles, authenticated installation,
  and the v1.6 mouse-independent profile boundary are unchanged.

## Release metadata

- Version: **1.5.6**
- Build: **29**
- Minimum macOS: **13.0**
- Architectures: **Apple Silicon and Intel**

## Verification

- The full source, routing, helper, App Profile, hit-test, deterministic preview,
  installer-integrity, and universal-package gates passed.
- All five Dashboard Height choices were rendered at their exact Retina sizes;
  decoded-pixel comparison rejects material differences while tolerating only
  low-level CoreGraphics antialias jitter across at most 0.2% of pixels.
- The minimum and maximum dashboard layouts were visually inspected with the
  same 940-point width.
