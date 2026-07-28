# Klik PRO next-update handoff

Updated 2026-07-28 after the owner selected v1.5.1 (build 24) as the next
development line. This is the starting point for the next engineering update.
Read this before changing profile or input behavior.

## Released baseline

- GitHub release: <https://github.com/AminudinMurad/klik-pro/releases/tag/v1.5.0>
- Release tag: `v1.5.0`
- Release commit: `66ce8ec` (the README follow-up is `acddca4`)
- Published branch: `release/v1.5.0`; `main` includes the README follow-up.
- Published app version/build: `1.5.0` / `23`.
- Current local branch after the README follow-up: `release/v1.5.0`.

## Active development baseline

- Next version/build: `1.5.1` / `24` in both app plists.
- Owner decision recorded: 2026-07-28.
- Active development branch: `codex/v1.5.1-development`.
- Keep the published v1.5.0 documentation and release assets unchanged while
  v1.5.1 remains unreleased.
- Add ongoing work beneath `1.5.1 (unreleased)` in `CHANGELOG.md`.

Do not change the app build number without an explicit owner decision. The
configuration schema version is independent from the app build number and may
advance when persisted data changes.

## Current continuation state

The v1.5.1 baseline contains:

- the synchronized `1.5.1` / `24` main-app and helper metadata;
- the final v1.5.0 README refresh and standalone release notes;
- an unreleased v1.5.1 changelog section;
- `tools/xcode-dev.sh` plus `docs/XCODE_DEVELOPMENT.md` for selecting the full
  Xcode toolchain and recording repeatable Instruments traces; and
- a full-check invariant that prevents either bundle from drifting away from
  version 1.5.1 build 24.

Last full verification:

```text
./tools/xcode-dev.sh check
All checks passed
build/check-20260728-192120
```

No v1.5.1 DMG/ZIP was built, installed, notarized, uploaded, or published. No
remote branch was pushed. The next engineering action is to choose one bounded
v1.5.1 roadmap item, measure the relevant baseline where performance is involved,
and add focused tests before changing behavior.

## What v1.5.0 delivers

The release is a stable mapping-preset implementation, not hardware-isolated
mouse routing. It provides:

- Up to three saved mapping presets, each with its own button toggles, shortcut
  combinations, Open App targets, browser selections, and display colour.
- One active preset at a time. Browsing a slide only loads it for editing;
  **Save** persists it and **Activate** makes it the helper's live preset.
- Fresh/reset colours: Pearl White, Mist Blue, and Rose.
- Fresh/reset defaults with all button toggles off; middle/gesture are Open App
  with no app selected; forward/back retain browser-history defaults; thumb-wheel
  switching is off by default.
- Shortcut recording, conflict checks, browser checkboxes, app/profile launch
  targets, and explicit Save/Discard handling on quit.
- Smoother carousel navigation, deterministic previews, and a compact mappings
  layout with three visible profile slides.
- Physical mouse assignment/scanning UI is intentionally not part of the public
  workflow. The current helper still applies one active mapping to supported
  mouse events, regardless of which physical mouse generated them.

## Source map

| Area | Main files | Notes |
|---|---|---|
| Persisted config and migrations | `Sources/KlikProConfig.swift` | Mapping presets, schema migrations, reset defaults, active profile. |
| Settings UI and carousel | `Sources/KlikProApp.swift` | Save/Activate, slide layout, browser picker, callout geometry. |
| Event helper | `Sources/KlikProInput.swift` | Reads the active mapping and handles supported events. |
| App discovery | `Sources/Duplication/AppScanner.swift` | Installed-app catalogue and icon discovery. |
| Routing/UI regression tests | `Tests/MouseButtonRoutingTests.swift`, `tools/MouseSlideHitTestMain.swift` | Hit testing, migrations, click routing, profile behavior. |
| Full verification | `tools/check.sh` | Builds/tests previews, permissions, launchers, icons, and release invariants. |
| Xcode and Instruments workflow | `tools/xcode-dev.sh`, `docs/XCODE_DEVELOPMENT.md` | Full-Xcode SDK selection, repository checks/builds, LLDB guidance, and repeatable traces. |
| Release packaging | `tools/build-release.sh`, `releases/install-klik-pro.sh` | Universal signed DMG/ZIP, checksums, signatures, local verification. |

## Required invariants

1. Keep `CFBundleShortVersionString` and `CFBundleVersion` in
   `App/Info.plist` and `App/KlikProHelper-Info.plist` identical.
2. Keep the development version at `1.5.1` / `24`. A later version bump requires
   another owner decision and a release-plan update.
3. Preserve existing mapping IDs and names during migrations. A deleted profile
   must stay deleted; migration should only add missing defaults once.
4. Save is the persistence boundary. Activate may save the selected preset as a
   convenience, but browsing or editing must not mutate the helper's live state.
5. Keep the current one-active-preset contract until true device routing is
   implemented and tested.
6. Do not reintroduce a misleading Assign Mouse/Rescan workflow unless it is
   backed by real event-source routing. Device enumeration alone is not routing.
7. Keep the app's Accessibility/Input Monitoring behavior explicit and fail safe.
8. Run `./tools/check.sh` before a handoff. For a release, also run
   `./tools/build-release.sh` and the installer `--verify-only` path.

## Recommended next-update workflow

```zsh
cd "/Users/aminudin/Documents/Business/Products/Klik PRO"
git switch codex/v1.5.1-development
git status --short
./tools/xcode-dev.sh doctor
./tools/xcode-dev.sh check
```

Make one bounded change at a time. For persisted config work, add migration
tests before changing the schema. For UI geometry, render deterministic mapping
fixtures and inspect all three slide positions. For input changes, test both
the event helper and the UI hit-test harness.

Before merging or releasing:

```zsh
./tools/check.sh
./tools/build-release.sh
./releases/install-klik-pro.sh --verify-only \
  --version v1.5.1 \
  --dmg releases/Klik-PRO-v1.5.1-macos-universal.dmg \
  --checksum releases/Klik-PRO-v1.5.1-macos-universal.dmg.sha256 \
  --signature releases/Klik-PRO-v1.5.1-macos-universal.dmg.sha256.sig
```

Do not install the release as part of a local build unless the owner explicitly
asks for installation. Keep release assets local until final manual testing is
complete, then publish the tag and release assets together.

## Known limitations and open decisions

- Mapping presets are not bound to hardware. All connected mice share the one
  active preset.
- `IOHIDManager` scanning can enumerate devices, but scanning does not identify
  the source of a `CGEventTap` button event.
- True per-device routing is documented separately in
  [`TRUE_MOUSE_PROFILE_PLAN.md`](TRUE_MOUSE_PROFILE_PLAN.md). Do not implement it
  by merely restoring or exposing the old assignment UI.
- Browser tab switching remains dependent on the browser's supported shortcut
  behavior and the device's wheel events.
- The app is ad-hoc signed and not notarized; the installer explains the normal
  Gatekeeper path and verifies the signed release manifest before installation.

## Handoff checklist

- [ ] Read this document and `TRUE_MOUSE_PROFILE_PLAN.md`.
- [ ] Confirm `git status` is clean and identify the active branch.
- [ ] Confirm app version/build before editing plist files.
- [ ] Decide whether the work is mapping-preset behavior or true hardware
      routing; do not mix the two models in one UI change.
- [ ] Add/update focused tests before running the full check.
- [ ] Render and inspect the affected preview fixture.
- [ ] Run the full check and record its output directory.
- [ ] Review the staged diff for accidental generated files, secrets, or AI
      attribution/trailers before committing.
- [ ] Build and locally verify the DMG only when the owner requests a release.
