# Klik PRO v1.5.1

Klik PRO 1.5.1 is a focused performance and layout release. The dashboard now
fits comfortably on a 13-inch MacBook, the background helper avoids expensive
unchanged-state signature rescans, and the Advanced tab has clearer spacing and
contained controls.

## Improvements

- **13-inch friendly dashboard.** The complete window is now 940×770 points and
  fits the default 1440×900 MacBook workspace without an outer scrollbar.
- **Lower idle CPU use.** Klik PRO fingerprints relevant profile files during its
  availability poll and repeats full health and code-signature validation only
  when those inputs change.
- **Validation remains fail-closed.** Full checks still run at startup and before
  every managed launch, so the performance improvement does not relax launcher
  verification.
- **Cleaner Advanced tab.** Data Folder and Profile Cleanup use aligned top cards,
  while App Profile Maintenance occupies a full-width panel below them.
- **Contained scrolling and actions.** Maintenance rows scroll inside their own
  panel, action buttons no longer overlap card boundaries, and the Save/Close
  footer no longer sits beneath a large detached blank area.
- **Xcode and Instruments workflow.** Contributors can select the full Xcode
  toolchain, run repository checks, and capture repeatable profiling traces with
  the new development bridge.

## Build

- Version: **1.5.1**
- Build: **24**
- Distribution: universal macOS DMG and ZIP for Apple silicon and Intel
