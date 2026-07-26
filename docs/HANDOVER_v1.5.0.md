# Handover — Klik PRO v1.5.0 (build 23)

Written 2026-07-25. Read this first if you are picking up mid-stream.

## Where the work lives

**Active dev line: `feature/1.4.2-native-dock`** — badly named (it carries v1.4.6 work, not v1.4.2).
It is **7 commits ahead of `main`, 0 behind**. `main` is the released v1.4.5 / build 22.

Recommended: continue on a clearly named branch cut from that HEAD, e.g.

```
git switch -c release/v1.5.0            # from feature/1.4.2-native-dock HEAD
```

Do **not** start from `main` — you would lose the seven commits below.

Unmerged commits (oldest → newest):

| Commit | Summary |
|---|---|
| `904e464` | docs: refresh handover — v1.4.3 shipped, v1.5 cancelled, next is v1.4.4 UI |
| `2a1fd68` | **feat: support Gemini app profiles via CFFIXED_USER_HOME (native engine)** |
| `9dc24d9` | fix: attest the real rule, and keep the keychain link resolvable |
| `a2de7e9` | docs: record Gemini native-engine support and the evidence still owed |
| `a756076` | Merge branch 'main' |
| `68bba96` | release: Klik PRO v1.4.6 (build 23) — Gemini App Profiles |
| `fae4b11` | docs: record that Gemini is not yet listed in the App Profiles UI |

## Decision: version is v1.5.0, not v1.4.6

Owner decision 2026-07-25. Both plists currently read **1.4.6 / 23** and must become **1.5.0 / 23**
(build number stays 23; v1.4.5 consumed 22). `tools/build-release.sh` aborts unless
`App/Info.plist` and `App/KlikProHelper-Info.plist` match exactly — they are in parity now, keep them so.

The old "v1.5 is reserved for the generator Rename/Change-Icon feature" note is **stale**: that feature
shipped in v1.4.2 (`bd2ab3d`) and `wip/v1.5-generator-rename-changeicon` no longer exists.

## What already works (do not rebuild)

Gemini App Profiles are implemented. `Sources/Duplication/EngineDetector.swift` holds
`com-google-geminimacos-native-untested` with detailed evidence comments. Key facts recorded there:

- Isolation is **`CFFIXED_USER_HOME` only**. Plain `HOME` does nothing — macOS Foundation resolves the
  home directory from the password database and ignores it (probe-verified). `--user-data-dir=` is
  suppressed for this rule because Gemini has no profile flag.
- Evidence on 1.86.7.600: five accounts isolated simultaneously, each with its own account slot,
  cookie jar and chat store; cold start restored a sign-in; re-verified after relocating a live
  profile into the vault.
- Known residual leak: `~/Library/Preferences/com.google.GeminiMacOS.plist` stays shared because
  cfprefsd resolves the per-user domain and ignores `CFFIXED_USER_HOME`. Affects feature flags and
  window frames only; accounts do not collide.
- Gemini registers **no URL scheme**, so it does not suffer the browser-callback misrouting that
  affects Canva/Zoom/Slack-style apps.

## The remaining gap — this is the work

**Gemini is not a `QuickLaunchTarget`,** so it never appears in the App Profiles generator, has no
native-app row, and gets no green-star original Dock launcher. Everything below hangs off that enum.

### 1. Add Gemini to `QuickLaunchTarget` (`Sources/KlikProConfig.swift:143`)

`enum QuickLaunchTarget: Int` currently has `chatGPT`, `claude`. Add `case gemini` (append, so the Int
raw value stays stable for existing configs) and fill all seven switches:

| Member | Gemini value |
|---|---|
| `title` | `"Gemini"` |
| `shortcutSlot` | `.geminiHotkey` — **new** case in `ShortcutSlot` |
| `applicationBundleIdentifier` | `com.google.GeminiMacOS` |
| `standardApplicationPath` | `/Applications/Gemini.app` |
| `launcherWrapperPath` | `~/Library/Application Support/Gemini Launchers/Gemini.app` |
| `originalDockLauncherPath` | filename `Gemini.app` |
| `originalDockLauncherBundleIdentifier` | `local.klik-pro.original.gemini` |
| `legacyInstanceID` | **open decision** — see below |

**Open decision:** `legacyInstanceID` returns a non-optional `UUID` identifying a v1.x legacy wrapper
row. Gemini never had one. Either make the property optional (cleaner; touches the migration paths and
`suppressedLegacyInstanceIDs` handling) or mint a fixed synthetic UUID. Recommendation: optional.

Config additions in the same file: `geminiHotkey: ShortcutMapping`, `geminiMouseButton:
QuickLaunchMouseButton?`, matching `CodingKeys`, decode defaults for older configs, and a
**schema bump 12 → 13**.

There are ~68 references to the existing cases. Swift's exhaustive switches plus the project's
`-warnings-as-errors` build will surface every site that needs a Gemini arm — let the compiler drive it.

**Verify at launch:** Gemini starts **windowless** unless `--full` is passed (its UI is
launcher/hotkey driven). Confirm how the managed launcher supplies arguments for a `.native` rule —
`Sources/KlikProManagedLauncher.swift:86` sets `configuration.arguments = payload.arguments`.

### 2. App Profile Generator card revamp (`Sources/AppProfilesUI.swift`)

Owner requirements, 2026-07-25:

1. **Compatibility badge** `Verified | Unverified` on each generator card. Source of truth is
   `AppCompatibilityAssurance` (`.verified` → "Verified", `.untested` → "Unverified"). **New plumbing:**
   nothing currently passes eligibility/assurance into the card — `AppProfilesUI.swift` has no
   reference to it today.
2. **Only apps in our catalogue appear**, each followed by its badge.
3. **Remove the "Installed" status line** — `statusField` at ~`:496` sets `"Installed"` (green) /
   `"Not installed"`.
4. **If a listed app is not installed, hide the card entirely.** Generator cards are built from
   `QuickLaunchTarget.allCases` at `Sources/KlikProApp.swift:1981`; filter there rather than
   rendering a disabled card.
5. **Move the Menu Bar Icon toggle into the gear menu** as the **last** item with a `.separator()`
   before it. Current pieces: `menuBarLabel`/`menuBarToggle` declared `:259-260`, positioned `:311`,
   change handler `:339`, state applied `:384`, enabled/disabled `:394`. The gear menu is built at
   `:403` and currently ends with `addNative` (`:464`) / `removeNative` (`:478`), with an existing
   `.separator()` at `:451`.
6. **No badge on the "Your App Profiles" column** — that is a different card class starting ~`:586`.
   No badge there. **But it does also lose its inline toggle** — see 8.
7. **All three targets are Verified** — Claude, ChatGPT and Gemini (owner calls 2026-07-25; owner is
   the verifier now, see the house rules). Set `assurance: .verified` on all three rules.

   **Rule ids: rename the two that are still free, now.** Ids are persisted per instance as
   `compatibilityRuleID` and re-validated at every launch
   (`eligibility.compatibilityRuleID == instance.compatibilityRuleID`), so an id becomes frozen the
   moment any profile stores it. Checked on 2026-07-25 — only Claude's is taken:

   | Rule id | Persisted by | Action |
   |---|---|---|
   | `com-anthropic-claudefordesktop-verified` | `Claude 2` (config + vault) | **keep** — frozen |
   | `com-openai-codex-untested` | nothing | rename → `com-openai-codex` |
   | `com-google-geminimacos-native-untested` | nothing Klik PRO tracks | rename → `com-google-geminimacos` |

   Putting assurance in the id was the original mistake; new rules must use assurance-neutral ids so
   the badge can change without touching the id. (Two hand-made Gemini launcher shims in
   `~/Applications/Klik PRO` carry the old id in their `LaunchSpec.plist`, but Klik PRO does not track
   them, so nothing validates against it.) If Claude's id ever needs cleaning, add a
   `previousIDs: [String]` field to `AppCompatibilityRule` and accept historical ids during validation
   — not required now.
8. **Move the menu-bar toggle into the gear menu on BOTH card types** — bottom-most, after a
   `.separator()`, rendered as a real **toggle switch, not a checkmark item**. `NSMenuItem` supports
   this via `item.view = …`, so reuse the existing `ToggleSwitchView` in a small container view rather
   than using `state = .on`.

   | Card | Gear menu built at | Current last items | Append |
   |---|---|---|---|
   | Generator (left) | `:403` | separator → Add Native Dock Icon `:464` → Remove Native Dock Icon `:478` | separator → Menu Bar Icon toggle |
   | App Profile (right) | `:716` | Rename… → Change Icon… → Add to Dock → separator → Remove from Klik PRO… | separator → Menu Bar Icon toggle |

   Right-column pieces to remove from the card body: `menuBarLabel`/`menuBarToggle` declared `:586-587`,
   constructed `:602`, laid out in row 1 near `:637-643`.
7. **Two rows, not three.** The generator card is currently 3 rows (name+toggle+gear / status /
   buttons). Removing the status line and moving the toggle into the gear menu leaves the intended
   **2-row** layout, matching the App Profiles card in the right column:

   ```
   ┌────────┐  Name  [Verified|Unverified badge]              [gear]
   │  ICON  │
   └────────┘            Open  + New Profile  (link) Assign Button
   ```

   Owner decisions on this layout:
   - **The icon spans both rows** — roughly 44×44, vertically centred, on the card's left. It is not
     an inline row-1 element any more; rows 1 and 2 stack in a column beside it.
   - **Keep the existing button labels verbatim** — "Assign Button" with its link icon, not "Assign".
     With the full label the generator's three buttons nearly fill the card width; if space gets
     tight at narrow window widths, drop the link icon rather than truncating the label.
   - **Row 2 is right-aligned in BOTH columns** — not indented under the name. The action row ends on
     the same vertical line as the gear, so the generator card (three buttons) and the App Profile
     card (two buttons) still line up across the two columns.

   The badge takes the space freed on row 1 and follows the app name. Card height must shrink
   accordingly — check the layout constants near `:298-350` and the height used by the enclosing
   card list so the two columns line up.

### 2b. Move the App Profiles tab's Refresh App List button

The two tabs currently disagree. **Mappings** places `⟳ Refresh App List` in a slim header row
**above both** the Native Apps and App Profiles cards, left-aligned, with the refresh icon
(`AppProfilesUI.swift:1069-1113`). **App Profiles** puts the same control at the top-**right** *inside*
the right-hand column, with no icon (`:1213`).

One button is correct — it performs a single operation (rescan installed apps) that both columns
depend on: the generator list is entirely derived from it, and the profile rows use it for health
(is the source app still installed, is the launcher intact). A second button would call the same
thing.

Fix: one refresh control per tab, in a header row **above both columns**, in both tabs. Do not add a
per-column refresh.

**Owner decision — icon-only, one per column, four in total.** Replace the full-width
`Refresh App List` button with a small clockwise-arrow icon placed **inline at the right of each
list's section header**, in all four lists (Mappings → Native Apps + App Profiles; App Profiles tab →
App Profile Generator + Your App Profiles). Every one calls the same `onRefreshApps` — a duplicated
affordance, not duplicated behaviour, so whichever column the user is reading has the control to hand.
Sitting inline with the section title, it also costs no vertical space, unlike the header row it
replaces.

Implementation: `title = ""`, `imagePosition = .imageOnly`, ~24–28pt square (icon ~13–14pt). Delete
the old standalone button and its header row in both tabs.

- All four **must** carry `toolTip = "Refresh App List"` — there is no label any more. Keep the
  accessibility label already set at `:1111`.
- **Glyph is already correct — do not change it.** The refresh control uses SF Symbol
  `arrow.clockwise` (`AppProfilesUI.swift:1102`), the same one as the Updates button
  (`KlikProApp.swift:8166`), which is the look the owner asked for. Only the label and pill differ.
  Separately, `KlikProApp.swift:540` uses `arrow.counterclockwise`; if that is also a rescan control
  it should move to `arrow.clockwise` (clockwise reads as refresh, counterclockwise as undo). The
  gear's Reset icon at `AppProfilesUI.swift:438` correctly uses `arrow.uturn.backward` — leave it.
- **Keep the icons' state in sync.** If refresh ever disables or animates during a rescan, all of them
  must do it together, or one will look broken.

### 2c. Mappings tab uses the SAME card layout

Owner decision: the Mappings tab's two lists (`NATIVE APPS`, `APP PROFILES`) must use **exactly** the
card designed in 2 — 44×44 icon spanning both rows, name row, right-aligned buttons, gear holding the
menu-bar toggle. Specifically:

- drop the **"Native app"** subtitle (same reasoning as dropping "Installed" — it is the third row)
- enlarge the icon, right-align the action row
- **add a gear** to Mappings rows (they have none today) — required, since the menu-bar toggle now
  lives inside it
- **badge shown on Native Apps** too: that list holds the same apps as the generator. The App
  Profiles list stays badge-free in both tabs.
- assigned buttons keep the green pill treatment (e.g. `Middle Button`)
- **no `+ New Profile` on Mappings** — that tab assigns buttons, it does not create profiles

Button matrix (the only difference between the four lists):

| Tab | List | Buttons |
|---|---|---|
| App Profiles | App Profile Generator | Open · **+ New Profile** · Assign Button |
| App Profiles | Your App Profiles | Open · Assign Button |
| Mappings | Native Apps | Open · Assign Button |
| Mappings | App Profiles | Open · Assign Button |
- `⟳ Refresh App List` stays top-left above both columns — Mappings already does this correctly

**Reclaim vertical space for the taller cards** (owner decision). Two independent gains, ~60–70pt total:

1. **Move the Mouse Profile card up** — tighten the gap between the tab bar and the card (~20–25pt).
   The card itself does not shrink; the mouse image and callouts keep their current size.
2. **Delete the Refresh App List row** (~40pt) — removing the 28pt control plus the gap above and
   below it. The icon moves into each column header at no vertical cost.

Give all of it to the two list columns.

Watch the height even so: rows grow from ~44pt to ~66pt, so three native apps now occupy what four
did. The reclaimed space buys back roughly one row. Once the generic fallback lands the Native Apps
list can reach 10+ entries, so the columns **must scroll internally** rather than pushing the Save
button off-screen.

### 3. Generic engine fallback — the core of v1.5.0

Owner decision: **no app should be stuck at zero because nobody supplied a disk image.** Rules must
not pre-pin an identity we cannot know; Klik PRO already inspects installed apps, so it can learn the
identity at runtime.

Three categories (owner's model): **Verified** = mechanism known and proven (app + doc);
**Unverified** = mechanism known, not proven (app + doc); **Untested** = MacDupl lists it but the
mechanism is unknowable until we see the app (**doc only**). Untested self-resolves — once installed,
engine detection turns it into Verified or Unverified. So the app shows **two** badges, the doc three.

**What already works (verified 2026-07-25):** `LauncherGenerator.swift:638` reads
`(rule?.passesUserDataDirArgument ?? true)` — **a nil rule already emits `--user-data-dir`**, so the
Electron/Chromium launch plumbing needs no new work.

**The only gate** is `InstalledApp.swift` →
`var allowsManagedProfile: Bool { kind != .unsupported && compatibilityRuleID != nil }`, combined with
`EngineDetector.eligibility()` (~`:246-252`) returning `.experimental` with **no** ruleID for an
unruled Electron/Chromium app.

**Change:**
1. `AppCompatibilityRule.bundleIdentifier` / `.teamIdentifier` become **optional** — nil bundle id
   matches any app of that engine, nil team id means don't pin. Update `matches()`.
2. Add `generic-electron` and `generic-chromium` registry entries: engine-matched,
   `assurance: .untested`, no `requiredEnvironment`, `passesUserDataDirArgument: true`.
3. `eligibility()` returns those ids in the `.electron` / `.chromium` fallback so
   `allowsManagedProfile` becomes true. `.gecko` and `.native` keep refusing — no generic recipe is
   safe for them (`CFFIXED_USER_HOME` is Foundation-specific and does nothing for Rust/Go apps, which
   is why Zed and Warp are excluded).
4. **Trust on first use** for the team id: capture it from the installed app at creation, persist it
   on the instance, validate against the stored value on later launches. Keeps the
   "app can't be swapped after you trusted it" guarantee without knowing the id up front.

Sandbox and App-Store checks already sit ahead of this path, so impossible classes stay blocked.

### 4. Docs

`docs/COMPATIBILITY.md` (Verified | Should work, two columns, failed apps never listed) was drafted in
the `continue-028969` worktree on the stale release branch — recreate or move it onto the v1.5.0 branch.
Then CHANGELOG + release notes for v1.5.0.

## 4b. List Canva, Zoom and Spotify — DO THIS NEXT

The owner's policy is settled: **if we know the mechanism, the app gets listed.** All three were
tested on 2026-07-25 and their mechanism is known, so they must appear. This is not a decision to
re-open — stop asking and implement it.

| App | Bundle | Team | Engine | Mechanism |
|---|---|---|---|---|
| Canva | `com.canva.CanvaDesktop` | 5HD2ARTBFS | electron | `--user-data-dir` (launcher emits it by default) |
| Zoom | `us.zoom.xos` | BJ4HAAB9B3 | native | `CFFIXED_USER_HOME: {profileDir}`, `passesUserDataDirArgument: false` |
| Spotify | `com.spotify.client` | 2FNC3A47ZF | native (CEF) | as Zoom. Note it enforces a single instance, so profiles are sequential |

**A registry rule alone is not enough today.** The generator column is built from
`QuickLaunchTarget.allCases` (`AppProfilesUI.swift`, `generatorCards`), so an app with a rule but no
enum case still renders nothing. Two ways forward:

1. **Cheap, scales badly** — add each as a `QuickLaunchTarget` the way Gemini was done. Every case
   needs a `ShortcutSlot`, a `<app>Hotkey` and `<app>MouseButton` in `KlikProConfig`, decode
   defaults, and arms in ~8 switches. Fine for three; unworkable at forty.
2. **Right fix** — make `QuickLaunchTarget.shortcutSlot` **optional** (`ShortcutSlot?`, nil = no
   global hotkey). A target then costs only title / bundle id / app path / dock-launcher id, with no
   config keys at all, and the generator can list every ruled app. Touches every `shortcutSlot`
   consumer once, then every future app is nearly free.

Take option 2. It is the same "stop pre-committing per-app plumbing" move that the generic engine
fallback in section 3 makes for identities.

## 4c. Mappings tab — DONE 2026-07-26

All four items below are implemented; §2c's card is now shared by all four lists.

1. **Refresh icons relocated.** ✅ Four icon-only `arrow.clockwise` controls, one inline at the right
   of each list's section header (Mappings → Native Apps + App Profiles; App Profiles tab →
   Generator + Your App Profiles). The old floating/corner buttons and the Mappings header row are
   gone, and that row's height went to the lists. All four call the same `onRefreshApps` and are
   driven together by `setRefreshControlsBusy(_:)` in `KlikProApp.swift`, so they can never disagree.
2. **Mappings rows use the shared 2-row card.** ✅ `MappingOriginalAppRowView` and
   `MappingAppProfileOpenRowView` were rebuilt on `AppCardMetrics` (56pt icon spanning both rows,
   name + badge + gear on row 1, right-aligned actions on row 2). The **"Native app" subtitle is
   deleted**, a gear was added to both lists to host the menu-bar toggle, and `+ New Profile` is
   omitted. `tools/check.sh` now asserts the subtitle stays gone.
3. **Badges wired.** ✅ `setCompatibility(verified:)` is fed from `candidate.eligibility.kind`
   (`.verified` → "Verified", `.experimental` → "Unverified"), which already derives from the matched
   rule's assurance. Shown on the generator column and Mappings' Native Apps; App Profiles lists stay
   badge-free in both tabs. Mappings reads it via `nativeAppCompatibilityVerified(_:)`, which shares
   the generator's candidate cache so the two lists cannot disagree.
4. **Assign disabled for slotless targets.** ✅ Canva/Zoom/Spotify have `shortcutSlot == nil`, so
   their Assign control is disabled with an explanatory tooltip on both the generator card
   (`setAssignable(_:)`) and the Mappings native row (`MappingNativeApp.assignable`) rather than
   looking live and silently doing nothing. A generic per-target assignment store is still the
   longer-term fix if these should become assignable.

Also fixed in the same pass:

- **Scroller handles are now proportional.** All three lists (both Mappings cards, the App Profiles
  list, and Advanced's App Profile Maintenance) were sizing their document view to
  `max(viewport, content)`. The scroller draws its handle as viewport/document, so padding the
  document toward the viewport forced a nearly full-length handle that barely moved. They now use the
  exact content height; `autohidesScrollers` still hides the scroller when everything fits.
- **Refresh gave no feedback.** A Mappings-initiated refresh passes `showLoading: false`, so the
  rescan ran but an unchanged app list re-rendered identically and the control looked dead. Every
  rescan now shows on all four icons.
- **Name truncation.** The card name field was sized from `NSString.size`, which excludes the text
  field cell's own inset, so labels truncated with space still beside them ("Claude" → "Clau…").
  It measures through the cell now.
- **App Profiles column header gap.** The headers sat at y=52 with nothing above them; tightened to
  `headerTopY = 24` and the column content moved up with it, giving the profiles list another row.
  The drawn titles and the refresh icons both read that constant instead of repeating a literal —
  the split is what let the refresh control drift out of the header originally.

### Pre-existing breakage found and fixed while verifying

None of these were caused by the UI work; all predated it and were blocking `tools/check.sh`.

- `klikProBrowserInstalled` was declared **below** `@main` in `KlikProApp.swift`. The preview
  renderer builds its app body with `awk '/^@main$/ { exit }'`, so every preview failed to compile.
  Moved above `@main` with a comment recording the constraint.
- Test fixtures still encoded the pre-§5 defaults. §5's "start quiet" change (Middle/Gesture off, no
  app pre-assigned) landed without updating them, and conflict evaluation short-circuits a disabled
  mapping to `.ok`, so several conflict/routing tests asserted badges that can no longer occur. The
  affected fixtures now state their own preconditions instead of inheriting them from
  `KlikProConfig.default`.
- `ShortcutSlot.allCases.count` was asserted as 6 (now 7 — Gemini's hotkey) and
  `KlikProConfig.default.schemaVersion` as 12 (now 13).
- `QuickLaunchTarget.legacyInstanceID` became `UUID?`, but `AppProfilesFoundationTests` still used it
  non-optionally and looped over `allCases` expecting every target to own a legacy row — only ChatGPT
  and Claude ever shipped one.
- The production registry grew to ten rules (Canva/Zoom/Spotify/Antigravity/browsers) while the test
  still asserted exactly three. The exact-count guard is kept, updated to ten, plus an id-uniqueness
  check since ids are persisted per instance.

### Still open from §4c

- **Rule ids and assurance (§2 item 7) are unchanged.** `com-openai-codex-untested` and
  `com-google-geminimacos-native-untested` still carry assurance in their ids, and both still read
  `.untested`, so they badge as "Unverified". The handover records an owner call that all three are
  Verified, but house rules make verification the owner's call, so this was left alone rather than
  changed. Renaming the two free ids is still safe; Claude's is frozen.

## 4d. List-order pin — DONE 2026-07-26

Owner request: *"for mapping tab, the app listing limit to 3 apps (let user pin any 3 apps) add pin
icon (right to gear icon) on each app card. by limiting app list to 3, add a gap after the refresh
button."* Plus three clarifications: the pin appears on **both** tabs' cards; **max 3 pins per app
list**, and a fourth pin must be refused until the user unpins; and **nothing is auto-pinned** —
recover the saved pins on launch, and if none are pinned leave it that way.

**Interpretation that reconciles all four messages: pinning REORDERS, it does not filter.** The
owner also said *"let the user scroll to find the assigned app… apps assigned with buttons has
nothing to do with card pinning."* Scrolling only exists if the rows are still there, and refusing
to auto-pin only makes sense if an unpinned list still shows apps — a filter-to-pinned reading would
give an upgrading user two empty lists. So the Mappings **viewport** is three cards tall and pinned
cards float to the top; nothing is ever hidden. If the owner actually wants hard filtering, the only
change needed is a `prefix` in `MappingAppProfilesView.rebuildRows` and the equivalent for natives.

### Storage — `KlikProConfig`, no schema bump

`topPinnedOriginals: [QuickLaunchTarget]` and `topPinnedProfileIDs: [UUID]`, following the
`menuBarPinnedOriginals` precedent exactly: property, explicit `CodingKeys` case, `decodeIfPresent
?? []`, memberwise default.

- **Do not bump `schemaVersion`.** `normalizedQuickLaunchConfig` pins the stored value to **12**
  unconditionally (`KlikProConfig.swift`), `check.sh` greps that literal, and the live `config.json`
  reads 12 — so a new `if schemaVersion < 13` gate would fire on **every** launch forever. Both
  existing additive fields set the no-bump precedent and say so in their comments.
- **Ordered `Array`, not `Set`.** Two reasons: pin order is meaningful (first pinned stays highest),
  and `Set` iteration order varies per process, which would make `check.sh`'s two fixture renders
  differ and fail its byte-comparison. `topPinnedFirst` therefore filters the ordered array and
  never iterates a set.
- **Two fields, not one** — natives are `QuickLaunchTarget`, profiles are instance UUIDs; the two
  lists have disjoint identity types and independent 3-pin budgets.
- **Keyed by UUID, never by index** — `synchronizedLegacyQuickLaunchInstances` reorders and can drop
  rows on every normalize, so an index would drift.
- `clampedTopPins` de-duplicates and trims to `KlikProConfig.topPinLimit` inside `normalize`, so a
  hand-edited file cannot exceed the cap (precedent: the `knownDataRoots` truncation).
- Stale pins are **deliberately not pruned**. A pin for an uninstalled app or deleted profile simply
  matches nothing, so reinstalling or restoring brings the pin back.

### The cap must not be able to lock the user out — bug found by rendering

Counting *stored* pins toward the cap deadlocks: pin three apps, uninstall them, and every remaining
card reports "already full" while the pinned cards no longer exist to unpin from. **This was real** —
reproduced in a rendered preview (`topPinnedOriginals = [gemini, canva, zoom]` with only ChatGPT and
Claude installed showed both remaining pins disabled), not a hypothetical.

The rule is now in `topPinsAdding` (`KlikProConfig.swift`): **only pins that resolve to a card
currently in the list consume a slot.** Because storage is clamped to the cap, adding a pin when the
stored list is already that long releases the unresolvable entries to make room — otherwise
`clampedTopPins` would silently discard the pin just added. Resolvable pins are never sacrificed, and
an unresolvable one is only released when its slot is actually needed, so the ordinary
uninstall → reinstall path still restores a pin.

Resolvability is per list: installed app (`quickLaunchTargetApplicationURL != nil`) for natives,
present-and-active instance for profiles. The **displayed** at-limit state uses the same count, or
the cards would disagree with the toggle — the controller supplies it for natives
(`installedTopPinCount()`), while each profile list derives it from the `visible` set it already
computes. `testTopPinsCannotDeadlockOnUnresolvablePins` covers all of it.

### Why pinning departs from the menu-bar-toggle discipline

`toggleMenuBarPin` / `toggleOriginalMenuBarPin` guard on `hasUnsavedConfigurationChanges` and call
`applySavedConfig()`. `applyTopPins` does **neither**, on purpose:

- It writes **only the pin field**, to **both** `config` and `persistedConfig`, then saves
  `persistedConfig`. So unsaved mapping edits survive, and `config != persistedConfig` is unchanged —
  no red "Unsaved changes" footer for reordering a list. The existing toggles need that guard only
  because they swap the whole struct into both snapshots, which would clobber in-flight edits.
- No `applySavedConfig()`: the input helper has nothing to apply, so a `kickstart -k` restart would
  be latency and permission churn for no effect.
- The `saveInProgress` / `appProfileLifecycleInProgress` guard **is** kept — both paths write
  `config.json`.
- `check.sh` asserts both departures (no `applySavedConfig` in `applyTopPins`, and the dual-snapshot
  write), because they are easy to "tidy" back into a bug.

### Geometry

`AppCardMetrics` gained `pinSize`/`gearPinGap` and `pinFrame(cardWidth:)`; `gearFrame` now derives
from `pinFrame` so the gear shifts left. All three cards sharing `gearFrame` get a pin, so the shift
is unconditional. `AppProfileInstanceRowView` keeps its own literals (it is 92pt, not the shared 86)
and places its pin by hand. Both row types that hide the gear for external launchers now fall back
to the **pin's** minX, not the card edge, or the title slides under the pin.

`MappingSectionCardView` derives its viewport from `topPinLimit` — 3 rows = 277pt against the 352pt
card — putting `scrollY` at 63 instead of 36, i.e. a 28pt gap under the refresh icon. Floored at 36
so a shorter card degrades rather than computing a negative origin.

### Verification

- `tools/check.sh` fully green, unsandboxed, including the two-render byte-comparison that would
  catch any nondeterminism in the ordering.
- New `testTopPinsPersistAndClamp` covers persistence, pin order, empty-on-upgrade and the clamp.
  Both pre-existing round-trip tests leave new fields at their defaults, so they would have passed
  green even if the field never persisted — that gap is why this test exists. Verified it actually
  bites by flipping the clamp's `prefix` to `suffix` (it failed) and by dropping the `CodingKeys`
  entry (that turns out to be a **compile** error, since `init(from:)` names the case).
- `topPinnedFirst` was extracted and exercised standalone: pin-order precedence, stability of
  unpinned rows, dangling pins inert, duplicate pins harmless, no row lost or duplicated, and
  identical output across 200 runs.
- All seven Mappings fixtures and the tracked screenshots re-rendered.
- **Verified end to end against the real app, not just unit tests.** `tools/PreviewMain.swift` gained
  an `all` value for `KLIK_PRO_PREVIEW_INSTALLED_TARGETS` (the gap §4c left open), so a config with
  pins can be seeded into `KLIK_PRO_CONFIG_DIRECTORY` and rendered. Confirmed through that path:
  pins decode from `config.json`; a pinned Claude is lifted **above** ChatGPT, reversing `allCases`
  order; the pinned pin renders filled and accent-tinted while unpinned ones stay grey; the viewport
  shows exactly three cards; and the deadlock above both reproduced and stopped reproducing
  (measured on the pin pill's luminance — 0.873 disabled vs 0.810 enabled — because the two states
  differ by only 0.03 alpha).
- That 0.03-alpha difference was itself too subtle to read, so `applyPinIconState` now also dims the
  **glyph** (`tertiaryLabelColor`) when a pin is unavailable, rather than relying on the pill and the
  tooltip alone.
- **`render-app-profiles-showcase.swift` scene 3 was re-cropped.** Its rect was framed for the old
  6-row list and, after the viewport change, showed the mouse card instead of the badged profile
  icons its caption describes. Note the `crop` is **top-left origin** (`sourceRect` flips it) — easy
  to get backwards. Nothing in `check.sh` verifies this framing, only that the GIF is non-empty, so
  re-check it by eye after any Mappings list geometry change.

### Still open

- **The showcase GIF's eyebrow still reads "KLIK PRO 1.2.2"** (`render-app-profiles-showcase.swift`).
  Pre-existing and unrelated to the pin; left alone rather than silently changed.
- **No *tracked* fixture covers a pinned state.** The states above were rendered ad hoc via a seeded
  `KLIK_PRO_CONFIG_DIRECTORY`; none of it is wired into `render-previews.sh`, so nothing re-checks the
  pinned treatment on future changes. `INSTALLED_TARGETS=all` now exists, so adding a
  `mappings-pinned.png` fixture is straightforward — it needs a preview override for the pin lists
  (profile pins are keyed by runtime-generated UUIDs and so cannot be seeded from config).
- **The disabled at-limit pin was never rendered.** It needs three pinned apps *and* a fourth
  unpinned card on screen at once, which this machine cannot produce: the Mappings viewport is three
  cards tall, and the generator column — the only uncapped list — shows a card per genuine candidate,
  which is just ChatGPT and Claude here (`INSTALLED_TARGETS` overrides path lookup, not candidate
  discovery). Covered by `testTopPinsCannotDeadlockOnUnresolvablePins` and by the tooltip/alert copy,
  but the visual is unverified. Worth an eyeball on a machine with three-plus catalogue apps
  installed.

## 4e. Mouse Profiles — SPEC ONLY, not built (owner decisions 2026-07-26)

The Mappings tab's device card already carries a carousel scaffold: `drawDeviceCard`
(`KlikProApp.swift`) draws disabled prev/next chevrons and one active page dot, with a comment
pointing at `mouse-profile-carousel`. This is the spec for filling it in.

**Owner decisions:**

- **Up to 3 mouse profiles**, one per carousel slide. Same cap as the list-order pin, so
  `clampedTopPins`-style clamping in `normalizedQuickLaunchConfig` is the precedent to copy.
- **Every profile exposes every control** — Middle, Gesture, Forward, Back, thumb wheel. No
  per-device filtering and **no HID detection work**: it is up to the user which controls they
  actually set. This composes with the blank defaults in §5: an unused control reads
  "No shortcut", so it is visibly unused rather than pre-claimed.
- **Two-step activation.** Chevrons/swipe browse; an explicit Activate commits. Switching
  rewrites hotkey registrations and kickstarts the helper, so it must not fire on every chevron
  press. The live profile carries an "Active" badge; the tab opens on the active profile, not on
  slide 1. Keep "viewed" (page dot) and "active" (badge) visually distinct.

**Owner decision NOT yet made:** whether the three app hotkeys (`chatGPTHotkey`, `claudeHotkey`,
`geminiHotkey`) belong per-profile or stay global. They are keyboard shortcuts, so having them
switch when the user slides to a different *mouse* profile may surprise. This changes the struct,
so settle it before writing the model.

### Implementation notes (the cheap path)

**Do not rewrite the ~150 call sites.** Extract `MouseProfile`, then keep today's property names
as computed proxies onto the active profile:

```swift
extension KlikProConfig {
    var middleButton: ShortcutMapping {
        get { activeMouseProfile.middleButton }
        set { mouseProfiles[activeMouseProfileIndex].middleButton = newValue }
    }
}
```

Every existing reader — the whole conflict engine and `KlikProInput`'s registration path — keeps
compiling and automatically operates on the active profile. That reduces the change to ~20 proxy
properties plus the storage layer.

**Boundary:** only the button/key surface belongs in a profile. App Profile instances, the vault,
`dataRoot`, menu-bar prefs and `topPinned*` stay global. Splitting this wrong later is expensive,
because mouse assignments reference instances by UUID.

**Traps, in order of how much they will cost:**

1. **The schema pin.** `normalizedQuickLaunchConfig` sets `schemaVersion = 12` unconditionally on
   every write and `tools/check.sh` greps that literal. This is the first change that genuinely
   needs a bump, so the pin must be lifted deliberately. Migration wraps today's top-level fields
   into `mouseProfiles[0]`, named "Default".
2. **Downgrade.** Dual-write for one release — keep the legacy top-level fields mirroring the
   active profile so a v1.5.x build still reads a sane config. Drop the mirror one release later.
3. **Validation becomes per-profile.** `appProfileAssignmentsAreValid` currently fails `save()`
   closed on any conflict. An *inactive* profile holding a duplicate is harmless: validate the
   active profile on save, and validate a profile on activation. Otherwise the user cannot save
   while editing a profile that is not live yet.
4. **Naming.** "App Profiles" already means isolated app instances. Use `MouseProfile` everywhere
   and never abbreviate to `Profile`, or `AppProfileInstance` vs `Profile` becomes unreadable.

**Leave one door open:** the natural successor is auto-switching per frontmost app. Keep
`activeMouseProfileID` as the single source of truth that either the user or a future rule engine
sets, rather than scattering "which profile is live" into the view. Costs nothing today.

**A new profile starts like a fresh install** — Forward/Back mapped, everything else unset. So
§4f's blank defaults become the new-profile template.

### Registering a physical mouse to a profile — FEASIBILITY PROVEN 2026-07-26

Owner question: can Klik PRO scan every connected mouse and let the user bind one to a profile?
**Yes for identity; the hard part is per-event routing.** Verified by running an `IOHIDManager`
probe (usage page 1 / usage 2) on the owner's Mac with two mice connected:

| Mouse | VID/PID | Transport | Serial |
|---|---|---|---|
| Logi M650 | `0x046D` / `0xB02A` | Bluetooth LE | `9A519428` |
| MX Master 3 Mac | `0x046D` / `0xB023` | Bluetooth LE | `3D4ED8C35E2A8362` |

- **Scanning is easy** — ~40 lines, no new dependency (`IOKit` is already imported by
  `KlikProInput.swift`).
- **Serials are present and unique**, so identity can be VID+PID+serial. That removes the "two
  identical mice are indistinguishable" worry.
- **The scan needs a filter.** The same match also returned `Apple Internal Keyboard / Trackpad`
  and `MX Keys Mac` — exclude built-ins (transport `SPI`) and beware keyboards advertising a
  pointer usage, or the UI would offer a keyboard as a registrable mouse.
- `0xb023` is confirmed as the MX Master 3 Mac — the model hardcoded in
  `gestureServiceMatchingDictionary()` (`KlikProInput.swift`) and in `KlikProConfig.swift`. The
  M650 at `0xB02A` therefore gets the generic controls but **no Gesture**, which matches
  `README.md`'s "Gesture isolation currently targets only the tested MX Master 3 Mac".

**Per-event attribution is the architectural risk.** Input flows through a `CGEventTap` reading
`.mouseEventButtonNumber`, and a `CGEvent` carries no reliable identifier for which physical mouse
produced it. Getting that needs `IOHIDManager` input-value callbacks (each value carries its source
device) — but the `CGEventTap` is also what lets Klik PRO *suppress* the original click, so you would
need both paths correlated by timestamp. That correlation is racy.

**Recommended path — avoid the rewrite.** Bind profiles to devices and switch the *active* profile on
device arrival/removal. The codebase already has that exact pattern:
`installGestureServiceArrivalObserver` / `gestureServiceDidMatch` watch IORegistry for the MX Master
arriving and re-apply configuration. Generalising it from one hardcoded VID/PID to a registered set
is incremental work on proven code. So "connect the M650 → its profile activates" is cheap; "both
mice in use simultaneously with different mappings" is what needs the input-path rewrite. With a
3-profile cap and one mouse in hand at a time, the cheap version is very likely sufficient.

## 4f. Blank shortcuts — DONE 2026-07-26

**Owner decision, final:** a fresh install maps **only Forward (`⌘]`) and Back (`⌘[`)**. Middle,
Gesture and all three app hotkeys ship with **no shortcut at all** — not merely disabled.

**Rationale (owner):** beyond the scroll wheel, the two side buttons are the pair essentially every
advanced mouse actually has, so they are the only controls Klik PRO can assume exist. Middle,
Gesture and the thumb wheel vary by model, so pre-mapping them would claim shortcuts on hardware
that cannot reach them. Klik PRO is explicitly not aimed at basic mice.

### How "no shortcut" is represented

`KeyCombo.unset` — a sentinel with `keyCode 0xFFFF` (real `kVK_*` codes are all `< 0x80`), plus
`var isSet: Bool`. **Not** `combo: KeyCombo?`, for two reasons measured at the time: an optional
touches ~90 call sites, and because `ShortcutMapping` uses synthesized `Codable` with a
non-optional `combo`, a config written with a null combo **fails to decode wholesale on an older
build**. The sentinel degrades gracefully instead.

`KeyCombo.displayString` returns **"No shortcut"** for an unset combo, matching the app's existing
empty-state idiom (`No browsers`, `No image chosen`, `No native apps installed`). Rejected `—`: a
bare dash inside a field that normally holds keystrokes reads as though it were the keystroke.

### THE RULE, if you touch any of this

**Anything that compares or registers a combo must check `isSet` first.** Every unset combo shares
one `signature`, so an unguarded comparison makes each blank row duplicate every other blank row.
Three guards exist and all three are load-bearing:

1. `evaluateShortcutConflicts` — `isSet` gates **only the duplicate verdict**
   (`if isDuplicate, mine.combo.isSet`). It must **not** be an early `continue` for the slot: a row
   linked to a launcher still has to inherit that launcher's reserved/extension warnings, which are
   about the launcher's combo, not this row's. An early return broke exactly that and was caught by
   `a linked mouse row must inherit its launcher's extension warning`.
2. `appProfileAssignmentsAreValid` — seeds `hotkeyOwners` from `{ $0.enabled && $0.combo.isSet }`.
   Without `isSet`, two blank rows collide and the validator fails **`save()` closed silently** for
   a perfectly legal config. Note a row can legitimately be enabled with no combo when it is in
   Open-App mode, where the combo is dormant.
3. `KlikProInput` — all three `RegisterEventHotKey` sites require `combo.isSet`. This is the most
   severe one: the sentinel key code would be rejected and the failure path calls **`exit(1)`**, so
   an enabled-but-unset hotkey would take the whole input helper down.

### UI

`applyUnsetShortcutPresentation` hides both the Reset control and the conflict badge on a blank row.
Reset because there is no default to return to; the badge because an unset combo cannot conflict, so
`✓ OK` beside it asserts a validated state for a shortcut that does not exist.

**Reset doubles as Clear, for free.** The existing handler sets the recorder to
`KlikProConfig.default.<x>.combo`, which is now `.unset` for these five rows — so `↺` on a
customised row means "back to nothing". That is the only route back to blank once a shortcut has
been recorded; without it, blank would exist solely on a fresh install. Forward/Back are unaffected
and still reset to `Browser →`/`Browser ←`.

### Test fixtures — expect this to bite again

Conflict evaluation short-circuits a **disabled** row to `.ok`, and now also ignores an **unset**
combo. So any fixture built from `KlikProConfig.default` that expects a Duplicate/reserved/extension
verdict must **state its own preconditions** — set `enabled = true` *and* an explicit combo. Six
fixtures in `Tests/MouseButtonRoutingTests.swift` and one in `Tests/AppProfilesFoundationTests.swift`
needed this. Symptom is a cascade: fix one assertion and the next one down fails for the same
reason. `git show HEAD:` on the test file plus a compile is the fastest way to confirm a failure is
yours rather than pre-existing.

### Not done

- **No fixture renders a blank row.** The `No shortcut` presentation, the hidden Reset/badge, and
  Reset-as-clear are unverified in pixels. Reachable now: `open -n --env
  KLIK_PRO_CONFIG_DIRECTORY=/tmp/kf "/Applications/Klik PRO.app"` writes a fresh config, and
  `PreviewMain` accepts `INSTALLED_TARGETS=all`.
- **The DMG in `releases/` predates all of this** — it is the 15:37 build with hotkeys still ON.
  Rebuild before shipping.
- **A fresh install still auto-creates 7 App Profiles** (`ChatGPT 1`, `Claude 1`, `Canva 1`,
  `Spotify 1`, `Gemini 1` + two legacy rows). Pre-existing, unrelated to this work, and arguably
  contradicts "starts quiet". Owner has not ruled on it.

## 5. Mouse Profile defaults (owner request, do next)

Change `KlikProConfig.default` (`Sources/KlikProConfig.swift`, the `static let default` block) so a
fresh install starts quiet, and only the two navigation buttons are live:

| Control | Wanted | Current default |
|---|---|---|
| Middle button | **OFF**, no app and no button assignment | `enabled: true` (⌘⇧7) **and** `chatGPTMouseButton: .forward` overlays elsewhere |
| Gesture button | **OFF**, no app and no button assignment | `enabled: true` (⌘⇧6) |
| Horizontal thumb wheel | **OFF** | `ThumbWheelConfig(enabled: true, chromeEnabled: true, braveEnabled: true, …)` |
| Forward button | ON, unchanged | `enabled: true` — leave alone |
| Back button | ON, unchanged | `enabled: true` — leave alone |

Also clear the default quick-launch overlays so no button arrives pre-assigned to an app:
`chatGPTMouseButton: .forward` and `claudeMouseButton: .back` both become `nil`
(`geminiMouseButton` is already `nil`). Note those two currently sit on Forward and Back, so leaving
them would contradict "no app assignment" even though the buttons themselves stay ON.

**Status 2026-07-26 — the default block is DONE.** `KlikProConfig.default` now reads: Middle off,
Gesture off, thumb wheel off, Forward/Back on with the browser Back/Forward combos, and
`chatGPTMouseButton` / `claudeMouseButton` / `geminiMouseButton` all nil. So on a fresh install no
mouse button is pre-assigned to an app, and the only buttons that arrive mapped are Forward and Back,
mapped to a **keyboard shortcut** (⌘[ / ⌘]), never to an app.

**Every per-browser checkbox also now defaults OFF** (owner call 2026-07-26), so the pull-down reads
"No browsers" on a fresh install and nothing is opted in on the user's behalf. This overrides the
"stored flags stay as they are" note below, which referred only to the installed-browser greying.
Existing configs keep their stored flags — it is a fresh-install default, not a migration.

**Thumb-wheel browser checklist — still open.** The per-browser checkboxes must reflect what is
actually installed — grey out and disable any browser that is not present, rather than offering it.
Detect by bundle identifier through the same app scan the rest of the tab uses
(`com.google.Chrome`, `com.brave.Browser`, `com.microsoft.edgemac`, `com.vivaldi.Vivaldi`).
Only the control's enabled state changes, so a browser that is uninstalled and later reinstalled
keeps its prior choice. `klikProBrowserInstalled(_:)` in `KlikProApp.swift` already does the
detection and the Settings checkboxes use it; it must stay **above** `@main` (the preview renderer
truncates the file there).

Bump the schema only if the decoder needs to distinguish an old config from a new one — existing
users should **keep** their current mappings; this is a fresh-install default change, not a migration.

## House rules that apply

- **Never copy code from MacDupl.** It is a third-party product; use it only as market signal for which
  apps are worth supporting.
- **No AI attribution** anywhere — no trailers, no co-author metadata. CI enforces this.
- **Verification is the owner's call.** Do not propose attestation/evidence gate runs; report findings
  plainly and let him decide.
- Browsers are excluded from the compatibility list by owner decision (Firefox explicitly — do not
  raise it again). Chromium browsers were queried and may be re-included; confirm before listing.
- `tools/check.sh` must be run **unsandboxed** — its preview-app launch stage fails in a sandbox with
  `kLSNoExecutableErr`.

## Verified app-target findings (tested 2026-07-25)

Works: Gemini (cleanest — no URL scheme), Canva, Zoom (data isolation; callback misroutes),
Spotify (isolation fine, but hard single-instance lock so profiles are sequential).
Fails and must not be listed: Telegram (app-group container resolved by `containermanagerd`),
WhatsApp and CapCut (sandboxed). Sandboxing is independent of download source — check the entitlement.

Cross-cutting limitation: apps registering a custom URL scheme (Canva, Zoom, Slack, Claude, ChatGPT,
Antigravity) send browser-login callbacks by **bundle identifier**, so the callback lands on whichever
instance LaunchServices picks — usually the native app. Not fixable in a launcher; the practical
workaround is quitting the native app during a profile's first sign-in.
