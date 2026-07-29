# Klik PRO next-update handoff

Updated 2026-07-29 for the v1.5.2 responsive-dashboard release.

## Released baseline

- Current public release: **v1.5.2 build 25**.
- Release tag: `v1.5.2`.
- Installed app at handoff: **v1.5.2 build 25**.
- Current local branch: `main`.

## v1.5.2 scope

- Version/build: **1.5.2 / 25** in both app plists.
- Scope: responsive dashboard and scalable long-list presentation only.
- Mouse mappings, mapping identities, configuration schema, and physical-event
  routing were not changed.

## Responsive design

The v1.5.1 940×770-point outer frame is retained as the minimum, not discarded.
The window can grow to 1280×960 and restores its last valid frame.

Settings offers five optional Best Fit outer-window frames:

| Display choice | Width | Height |
|---|---:|---:|
| 13-inch M1 | 940 | 770 |
| 13-inch M2+ | 1000 | 820 |
| 14-inch | 1080 | 860 |
| 15-inch | 1180 | 900 |
| 16-inch | 1280 | 960 |

These choices only set the frame. The window stays freely resizable and reports
non-matching frames as Custom.

The dashboard keeps a centred 872-point content canvas. Wider windows gain calm
side gutters instead of stretched controls. Additional height expands the
independent Native Apps, App Profiles, generator, and maintenance viewports; each
still scrolls when its content exceeds the available height.

## Verification evidence

- All routing, helper, LaunchAgent, App Profile, and UI hit-test checks passed.
- Two independently rendered preview sets matched byte for byte.
- Responsive fixtures matched their expected Retina dimensions.
- Minimum and maximum layouts were visually inspected.
- Inspection copies are in `build/v1.5.2-responsive-previews/`.
- Advanced long paths truncate before their action controls.
- Live isolated AppKit QA passed all five presets, custom resizing, minimum and
  maximum clamps, native zoom/restore, and compact/expanded list scrolling.
- Accessibility actions exposed the Best Fit radio group correctly. Injected QA
  focus proved Right Arrow navigation and Space activation without changing the
  Mac's global keyboard setting.
- Isolated Save → normal quit → relaunch retained the edited configuration and
  exact preset/custom frames. Invalid and off-screen stored frames recovered.
- Authenticated installed-app acceptance passed against
  `/Applications/Klik PRO.app`:
  - all five Best Fit controls applied their exact frames;
  - continuous manual resizing reported a valid Custom frame;
  - Save → normal quit → relaunch retained both the edited menu preference and
    the exact 15-inch frame;
  - the original menu and Caffeinate preferences were restored through the UI,
    saved, relaunched, and matched the complete pre-test configuration snapshot.
- Final pre-commit full gate: `build/check-20260729-170907` — passed.
- `git diff --check` passed.

## Release assets

The GitHub release carries nine authenticated assets: universal DMG and ZIP
archives, their signed SHA-256 manifests, the standalone installer, and the
installer's signed manifest. Treat source verification, installed-app acceptance,
packaging, publication, and public download verification as separate gates.

## Required invariants

1. Keep the main and helper version/build metadata identical.
2. Keep Save as the persistence boundary.
3. Preserve existing mapping IDs, names, and the one-active-mapping contract.
4. Do not change configuration schema for this UI-only release.
5. Do not expose device assignment unless physical event-source routing is real
   and tested.
6. Keep Accessibility/Input Monitoring behavior explicit and fail safe.
7. Run `./tools/check.sh` after any further source change.

## v1.6 boundary

v1.6 is reserved for mouse-independent profiles. The current helper still applies
one active mapping to supported mouse events regardless of the physical mouse.
`IOHIDManager` enumeration does not establish the source of `CGEventTap` events.
Read `TRUE_MOUSE_PROFILE_PLAN.md` before changing this model.

## Source map

| Area | Main files |
|---|---|
| Responsive window and presets | `Sources/KlikProApp.swift` |
| Expanding list viewports | `Sources/AppProfilesUI.swift` |
| Preview frame injection | `tools/PreviewMain.swift` |
| Responsive fixture matrix | `tools/render-previews.sh` |
| Full verification | `tools/check.sh` |
| Release notes | `docs/RELEASE_NOTES_v1.5.2.md` |
| v1.6 design boundary | `docs/TRUE_MOUSE_PROFILE_PLAN.md` |
