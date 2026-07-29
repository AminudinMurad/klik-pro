# Klik PRO next-update handoff

Updated 2026-07-29 for the resumed v1.5.3 release candidate.

## Released baseline

- Current public release: **v1.5.2 build 25**.
- Release tag: `v1.5.2`.
- Installed app at handoff: **v1.5.2 build 25**.
- Current local branch: `codex/v1.5.3-header-save-layout`.

## v1.5.3 release-candidate state

- Source version/build: **1.5.3 / 26** in both app plists.
- Release source and release notes are prepared but remain uncommitted.
- Public screenshots were regenerated from the final layout.
- The user resumed and authorized the v1.5.3 GitHub release with its changelog
  after the earlier handoff interrupted the final pre-commit gate.
- The final pre-commit gate passed at `build/check-20260729-215001`. Continue
  with the attribution gate, commit, universal packaging, installed-app
  persistence acceptance, annotated tagging, nine-asset publication, and
  public-download verification.
- Mouse Mappings uses the selected five-card geometry:
  Horizontal Thumb Wheel top-centre; Middle and Back above; Forward and Gesture
  below; the mouse and teal leaders remain centred.
- Each physical-button card has a compact header/status row and one aligned
  action/value/reset row. Open App remains supported in the same footprint.
- The header groups disk-icon Save, Close, and Power Off. Unsaved/apply/save
  feedback appears under the group.
- Close and the native red traffic-light route through the same Save / Discard /
  Cancel protection as Cmd-Q, Dock Quit, and normal menu-bar Quit. Power Off has
  its own confirmation, stops the helper, and turns off Launch at login.
- Check for Updates is inside Settings > About. Permissions uses one status row
  and one aligned Open Settings / Recheck / Reset / Logs action bar.
- Settings > Best Fit follows the Sistem PRO tile pattern: five MacBook
  silhouettes with exact Klik PRO outer-frame sizes, green active selection,
  a dedicated current-size row, and one resize-guidance row. The actual Klik PRO
  preset dimensions and minimum remain unchanged.
- The Mouse Mappings stage grows from 304 to 374 points while the app-list
  minimum remains 248 points. The 940×770 minimum and all five responsive
  presets are unchanged.
- Configuration schema and physical-event routing are unchanged. v1.6 remains
  the mouse-independent profile milestone.

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

- v1.5.3 final release-candidate gate passed at `build/check-20260729-215001`.
- A later release-gate rerun at `build/check-20260729-213931` was manually
  interrupted for this handoff after routing, hit-test, LaunchAgent,
  App Profiles, preview rendering, and the reported UI isolation checks passed.
  Do not treat that interrupted run as the final release gate.
- Two independently rendered v1.5.3 fixture sets matched byte for byte, including
  the minimum Settings/Permissions composition and the About-card Updates hover.
- Live isolated Best Fit QA exposed one radio group with five radio buttons,
  applied 13-inch M2+ by Right Arrow, applied 16-inch by click, and restored the
  exact 13-inch M1 940×770 outer frame.
- Live isolated AppKit QA verified all three header actions through Accessibility:
  - Close presented Save / Discard and Close / Cancel for a staged draft.
  - Power Off first protected the draft, then presented its separate stop and
    Launch-at-login warning.
  - Cancelling Power Off kept the dashboard open.
  - Confirming Power Off terminated only the isolated preview; the installed
    v1.5.2 helper remained running and its launch-at-login preference stayed on.
  - Save → Close → relaunch retained the edited menu-bar preference in the
    isolated `config.json`.
- `git diff --check` passed after the header and Settings rework.

v1.5.2 release evidence retained below:

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
| Release notes | `docs/RELEASE_NOTES_v1.5.3.md` |
| v1.6 design boundary | `docs/TRUE_MOUSE_PROFILE_PLAN.md` |
