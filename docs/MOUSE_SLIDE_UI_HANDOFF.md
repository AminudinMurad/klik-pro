# Mouse slide UI redesign — implementation handoff

Status: implementation completed; continuation QA handoff
Owner decisions recorded: 2026-07-26  
Branch: `release/v1.5.0`
Next operator: Claude

This handoff is the current continuation source for Claude. Preserve every commit
on this branch as authored: none contains `Co-authored-by`, `Generated-by`,
`Assisted-by`, or other AI attribution trailers, and
`.github/workflows/no-ai-coauthor-metadata.yml` rejects both those trailers and any
Claude/Anthropic author or committer identity.

## Gear button root cause — resolved 2026-07-27

The gear did not open its menu because the click never reached the button. Two
earlier attempts (`be6ac3b`, `941be25`) both assumed the menu opened and was then
immediately dismissed, and so changed *when* the menu is presented. The menu was
never presented at all.

`MouseProfileHeaderView` is a transparent overlay across the whole 872×344 mouse
card, so it carries a custom `hitTest(_:)` that lets clicks fall through to the
mapping rows beneath it while keeping its own gear and arrows clickable. That
override did:

```swift
let childPoint = subview.convert(point, from: self)
if let hit = subview.hitTest(childPoint) { return hit }
```

`NSView.hitTest(_:)` takes a point in the **receiver's superview** space — a
subview compares the point against its own `frame`. Converting into the subview's
local space first therefore subtracts its frame origin a second time. The gear
(frame origin x = 826) was tested 826pt to the left of where it is, and both
navigation arrows (origin y = 146) 146pt above themselves. All three controls
returned `nil`, the overlay reported no hit, and every click fell straight through
to `MouseSlideContainerView`.

So the gear **and both slide arrows** were completely dead — not just the gear.
The fix converts once from the superview and hands that point to the children
unchanged.

Two further defects were fixed alongside it:

- `AppProfileGearButton.mouseDown(with:)` presents from mouse-down and does not
  call `super`, which also skipped NSControl's own disabled guard, so a greyed-out
  gear would still have opened its menu. It now rechecks `isEnabled`.
- `presentMenu()` gained a re-entrancy guard and releases `presentedMenu` through
  `defer`, so a menu can never be stacked on a live tracking session.

### Why the previous run of `./tools/check.sh` exited silently

Not an environment problem. `tools/check.sh` carried a source guard pinning the
deferred-popUp workaround:

```bash
grep -q 'DispatchQueue.main.async { \[weak self, weak menu\] in' …
```

Commit `941be25` deleted that code, so the guard could never match again. A bare
`grep -q` under `set -euo pipefail` prints nothing when it fails, so every run
after `941be25` exited 1 in silence at that line. It was misread as the generated
preview-launch boundary. The guard now pins the current mouse-down presentation
instead, and rejects a return to the deferred popUp.

### Regression cover

`tools/MouseSlideHitTestMain.swift` drives the real `MouseProfileHeaderView`
through the real hosting chain (window → scroll view → flipped document →
`MouseSlideContainerView` → overlay) and asserts which view a click actually lands
on. It discovers the gear and arrows from the live subviews rather than hardcoding
their frames, so moving a control cannot make it quietly stop testing them. It
also asserts the overlay still lets clicks through to controls beneath it, and
that a disabled gear stays inert.

`check.sh` runs it after the mouse-button routing tests. Verified to fail on the
pre-fix code and pass after it.

An opt-in end-to-end mode additionally dispatches a real left-mouse-down at the
gear and confirms an `NSMenu` begins tracking with all eight specified items plus
the device submenu, its rescan action and its empty-scan copy. It needs a window
server and runs a menu-tracking loop, so it is deliberately not part of the
default run:

```bash
"$(ls -td build/check-* | head -1)/mouse-slide-hit-test" menu
```

## Current continuation state (2026-07-27)

Implemented in the current source:

- Mouse slide card height increased to 344 points, with the mouse artwork and
  controls vertically rebalanced.
- Native-app and App Profile list content starts closer to its section title,
  returning useful height to the slide/list area.
- Refresh controls use a native `NSProgressIndicator` spinner instead of the
  earlier rotating glyph animation.
- The mouse gear menu begins native AppKit menu tracking directly from the gear
  button's mouse-down event, matching native pull-down controls, and retains the
  menu for the synchronous tracking session.
- Space/Return and accessibility-triggered gear activation remain wired through
  the button's ordinary action path.
- The gear menu contains activation, assignment/rescan/unassignment, add,
  rename, duplicate, reset and delete actions as specified below.
- The gear and both slide arrows are reachable by a real click again; see the
  root-cause section above.

Live QA already confirmed the earlier DMG build displays the improved spacing
and native spinner treatment. Remaining manual QA on the current build: confirm
keyboard activation of the gear with Space/Return, exercise one non-destructive
menu item or submenu, and browse with the side arrows and a trackpad swipe. Use
an isolated temporary configuration and do not install or publish the app.

The DMG background/arrow remains unresolved in the mounted Finder view. Do not
claim that the DMG arrow is fixed without fresh visual verification.

Read this document before changing the Mappings mouse slide. Also read:

- `docs/MOUSE_DEVICE_ROUTING_PROPOSAL.md`
- `docs/HANDOVER_FINAL_2026-07-26.md`
- `docs/HANDOVER_v1.5.0.md`

## 1. Current handoff/test build

The latest replacement DMG was built from source commit:

```text
941be25 fix: open mouse mapping menu on mouse down
```

Path:

```text
releases/Klik-PRO-v1.5.0-macos-universal.dmg
```

SHA-256 at build time:

```text
3c54551d68e62600127728b504057ad9474aa9da224aadd75e139c1f8a0a7aa4
```

`./tools/build-release.sh` completed successfully in
`klik-pro-release-v1.5.0-20260727-004604.USG9Jl`. It verified the app and nested
helper signatures before and after packaging, verified the disk-image checksum,
and regenerated signed checksum manifests. This is a local handoff/test artifact;
it has not been published.

Important: `16d6dcf` is documentation only. True per-device event routing is not
implemented. Do not copy, translate, adapt or derive OpenLogi code.

The untracked `Klik PRO - sample icons/` folder is unrelated owner material. Do
not stage or modify it.

## 2. Final owner decisions

### Mouse controls

- No mouse-model capability database.
- Do not restrict controls based on model, VID/PID or assumed hardware features.
- With **no mouse assigned**, all five toggles remain visible but disabled and
  greyed out.
- After the user assigns **any mouse**, all five toggles become available:
  Middle, Forward, Back, Gesture and Horizontal Thumb Wheel.
- The user has complete freedom to configure and test every control.
- An unsupported physical control simply produces no event.
- Unassigning a mouse disables the controls without deleting saved settings.

Commit `23bd96c` implements the toggle visibility/availability rule. Preserve it
through the redesign.

### Terminology

“Mouse Profile” is potentially misleading because true event-source routing is
not yet implemented. Prefer **Mouse mappings** or **Mapping set** in new copy,
unless the owner later decides to retain the existing label for continuity.

Renaming a mapping set must never rename the physical mouse. Keep these separate:

```text
Mapping name: Office
Assigned mouse: Logi M650
Hardware identity: VID/PID/serial where available
```

### Cleaner slide layout

The current top row is too crowded. Remove the inline collection of profile
picker, chevrons, add button, dots, mouse picker, Activate button and ellipsis.

Replace it with:

- One gear icon at the upper-right of the mouse slide.
- A previous-slide button on the left edge.
- A next-slide button on the right edge.
- Current slide/profile name centred at the bottom.
- Page-position dots adjacent to the bottom name.
- Horizontal MacBook trackpad swipe to browse slides.

Browsing must remain different from activation:

- Arrow, swipe or dot navigation changes the **viewed** mapping only.
- It must not activate that mapping or change live mouse behavior.
- Activation remains an explicit gear-menu action.
- The tab opens on the active mapping.

Do not wrap from the final slide to the first or vice versa. Disable/dim the
corresponding arrow at each boundary.

## 3. Gear menu specification

Use the current mouse-profile ellipsis menu's visual format and native menu-item
behavior as the precedent. Consolidate profile management and association into
one gear menu.

Recommended order:

```text
Activate “<profile name>”       (disabled when already active)
Assign Mouse… / Change Mouse…
Unassign Mouse                  (disabled when none assigned)
—
Add Mapping
Rename Mapping…
Duplicate Mapping
Reset Mapping…
Delete Mapping…                (disabled for final mapping or active mapping,
                                following current safety rules)
```

Requirements:

- Use one standard gear icon consistent with App Profile card gear controls.
- Remove the separate top-row Activate button, mouse popup, add button and
  ellipsis after equivalent gear-menu operations work.
- “Assign Mouse…” should present connected mice and a rescan action. Preserve a
  recognizable cached product name for disconnected assignments.
- Show a temporary “Scanning for mice…” state while enumeration runs.
- Completed empty scan copy: “No compatible external mice found.”
- Do not expose only an opaque `Assigned mouse 046D:…` label when a current or
  cached friendly name exists.
- Keep current confirmation alerts for Reset/Delete where destructive.
- Keep the maximum of three mapping sets.

The exact menu wording may stay “Profile” if the owner has not approved a global
terminology migration. Do not mix “Profile” and “Mapping” casually within one
menu.

## 4. Bottom slide indicator

Desired composition:

```text
             ○  ●  ○    Office
```

or, if it balances better:

```text
             Office    ○  ●  ○
```

Requirements:

- The bottom label is the viewed slide's user-defined name.
- One dot per mapping set, maximum three.
- The viewed dot is filled/accented; others are neutral.
- Active runtime state must remain distinguishable from viewed state. A small
  “Active” badge beside the name is acceptable when the viewed slide is active.
- Dots may be clickable if implemented accessibly, but arrows and swipe are the
  required navigation mechanisms.
- Provide accessibility labels such as “Mapping 2 of 3, Office.”

## 5. Trackpad swipe behavior

Yes, native macOS horizontal trackpad navigation is feasible.

Implement on the mouse-slide view, not globally:

- Observe horizontal gesture/scroll events only while the pointer is over the
  slide.
- Accumulate horizontal delta across a gesture.
- Ignore predominantly vertical scrolling.
- Trigger once after a deliberate distance/velocity threshold.
- Lock until the gesture ends so one swipe cannot skip two slides.
- Natural-direction behavior should feel consistent with macOS paging.
- Animate the outgoing/incoming slide horizontally.
- Respect Reduce Motion: crossfade or switch without translation.
- Do not intercept scrolling over an open popup/menu.
- Arrow buttons and swipe must call the same browse function.

Possible AppKit approaches include a local `scrollWheel(with:)` implementation
using precise scrolling deltas and phase/momentumPhase, or an appropriate gesture
recognizer. Choose the smallest reliable approach and test on a real trackpad.
Do not use swipe to activate.

## 6. Side navigation buttons

- Place a large but visually quiet previous button at the vertical centre-left
  edge of the slide.
- Place the matching next button at the centre-right edge.
- Use standard chevron symbols and gear-consistent sizing/stroke.
- Maintain a generous hit target even if the glyph is small.
- Disable and grey the left arrow on the first slide.
- Disable and grey the right arrow on the final slide.
- Add accessibility labels and keyboard focus support.
- Left/Right arrow keyboard navigation is desirable when the slide itself has
  focus, but must not interfere with popup controls or shortcut recording.

## 7. Excess bottom-space correction

Current constants in `Sources/KlikProApp.swift`:

```swift
static let deviceCard = NSRect(... height: 360)
static let mappingBottomCard = NSRect(... y: 376, height: 352)
```

The visible controls end around 280 points, leaving roughly 80–100 points of
unused space. The guide was enlarged for an older layout and was not reduced
after controls were compacted.

During the redesign:

- Target a mouse-slide height near 310–320 points, subject to pixel inspection.
- Move `mappingBottomCard` upward by the same reduction.
- Rebalance total content height so the app lists gain useful space.
- Keep adequate clearance below the bottom label/dots and side arrows.
- Do not simply crop the existing slide: reposition the bottom indicator first.
- Recheck leader lines and mouse artwork after every geometry change.

The owner's screenshot is the visual source of intent: compact top area, centred
mouse controls, bottom name/dots, side navigation and no large blank lower band.

## 8. Primary implementation locations

Main file:

```text
Sources/KlikProApp.swift
```

Relevant types/functions as of `23bd96c`:

- `MouseProfileHeaderView`
- `SettingsContentView`
- `SettingsContentView.deviceCard`
- `SettingsContentView.mappingBottomCard`
- `RecordableShortcutRowView`
- `RecordableShortcutRowView.applyCompactStackedLayout()`
- `SettingsContentView.setMouseControlsAvailable(_:)`
- `refreshMouseProfileEditor()`
- `wireMouseProfileCallbacks()`
- `addMouseProfile()`
- `renameMouseProfile(_:)`
- `duplicateMouseProfile(_:)`
- `resetMouseProfile(_:)`
- `deleteMouseProfile(_:)`
- `bindMouseProfile(_:to:)`
- `activateMouseProfile(_:)`

Current state distinction:

```text
viewedMouseProfileID       carousel/editor selection
config.activeMouseProfileID runtime-active mapping
```

Preserve that separation.

Model and validation:

```text
Sources/KlikProConfig.swift
Tests/MouseButtonRoutingTests.swift
```

Preview/test infrastructure:

```text
tools/PreviewMain.swift
tools/check.sh
tools/render-previews.sh
```

## 9. Suggested implementation sequence

1. Capture a current preview/screenshot as the before-state.
2. Refactor `MouseProfileHeaderView` without changing callbacks:
   - keep browse/activate/add/rename/duplicate/reset/delete/bind operations;
   - route them through the new gear and side arrows.
3. Add bottom name and dots.
4. Add side navigation and boundary disabled states.
5. Add swipe handling calling the same `onBrowse`.
6. Remove redundant top-row controls only after their gear equivalents work.
7. Reduce the slide/card height and move the app-list card upward.
8. Preserve `setMouseControlsAvailable(profile.deviceIdentity != nil)`.
9. Add focused model/UI source guards and preview fixtures.
10. Inspect pixels manually at normal and Retina scale.
11. Run the full test suite.
12. Commit the UI change separately.
13. Build and verify a new DMG using the official release script.

## 10. Acceptance tests

### Navigation

1. One mapping: both arrows disabled; one active dot.
2. Two mappings: first slide disables left only; second disables right only.
3. Three mappings: middle slide enables both arrows.
4. Arrow browsing changes viewed content but not active runtime mapping.
5. Swipe left/right changes exactly one slide per gesture.
6. Vertical trackpad scrolling does not change slides.
7. Swipe at first/last boundary does nothing safely.
8. The bottom name and dot update after every browse.

### Gear menu

9. Activate is disabled on the already-active mapping.
10. Activate changes runtime mapping and active indication.
11. Add stops at the three-mapping cap.
12. Rename updates the bottom label immediately.
13. Duplicate copies expected mappings but not forbidden device ownership.
14. Reset preserves the currently assigned device if that is the existing
    product decision.
15. Delete obeys final/active mapping safety restrictions.
16. Assign, rescan and unassign update availability immediately.

### Controls

17. No assigned mouse: all five toggles visible, disabled and grey.
18. Any assigned mouse: all five toggles enabled, regardless of model.
19. Unassigning disables controls without deleting their values.
20. No mouse capability database or VID/PID-specific disabling exists.

### Layout/accessibility

21. No large empty band below the mouse/control content.
22. Bottom name/dots do not collide with artwork or app lists.
23. Side arrows have accessible labels and keyboard focus.
24. Gear menu is reachable by keyboard.
25. Reduce Motion behavior avoids sliding translation.

## 11. Verification and release procedure

Do not rely on a piped command's exit status. Run:

```bash
./tools/check.sh
```

The complete command must exit 0.

Then commit the tested source. Do not include `Klik PRO - sample icons/`.

Build:

```bash
./tools/build-release.sh
```

The script must:

- build version 1.5.0 (23), unless the owner explicitly requests a bump;
- validate app and helper signatures;
- verify the mounted DMG contents;
- report a valid `hdiutil` checksum;
- regenerate checksum and signature files.

Finally report:

- commit hash;
- DMG absolute path;
- SHA-256;
- test result;
- exactly which requested behaviors are implemented;
- any behavior still pending.

## 12. Out of scope for this UI iteration

- True simultaneous per-device event routing.
- Copying or translating any OpenLogi code.
- Maintaining a model capability database.
- Automatically disabling Gesture/thumb wheel based on mouse model.
- Renaming physical hardware when a mapping is renamed.
- Changing App Profile behavior unrelated to the mouse-slide layout.
