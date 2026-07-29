# Klik PRO v1.5.2

Klik PRO 1.5.2 turns the compact 13-inch dashboard into the minimum size of a
responsive workspace. It keeps the existing mouse-mapping and App Profile model
unchanged; mouse-independent profiles remain planned separately for v1.6.

## Highlights

- **Resizable dashboard.** Resize normally from the 940×770-point minimum up to
  1280×960 points.
- **Five Best Fit presets.** Settings can apply suggested frames for 13-inch M1,
  13-inch M2+, 14-inch, 15-inch, and 16-inch MacBooks. Manual resizing remains
  available after choosing one.
- **More apps without a larger minimum.** Taller frames show more Native Apps
  and App Profiles in Mappings and App Profiles, plus more Advanced maintenance
  rows. Each list keeps independent scrolling for overflow.
- **Stable reading width.** Cards stay on a centred 872-point canvas at larger
  sizes instead of becoming excessively wide.
- **Remembered window frame.** The last dashboard size and position are restored
  and constrained to the current screen.

## Release metadata

- Version: **1.5.2**
- Build: **25**
- Minimum macOS: **13.0**
- Architectures: **Apple Silicon and Intel**

## Quality checks

- The complete automated source, routing, helper, App Profile, UI, and packaging
  gate passed on both supported architectures.
- All five Best Fit layouts were rendered at their exact Retina dimensions and
  visually inspected at the minimum and maximum dashboard sizes.
- Live AppKit testing covered continuous custom resizing, minimum and maximum
  clamps, native window zoom and restore, independent long-list scrolling,
  keyboard-accessible Best Fit controls, and frame recovery across relaunches.
- The universal DMG and ZIP include signed SHA-256 manifests. The authenticated
  installer verifies the release key, version, architectures, and code-signature
  integrity before replacing an existing installation.
