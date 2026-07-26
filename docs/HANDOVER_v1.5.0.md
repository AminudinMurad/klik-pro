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

## 4c. Mappings tab still untouched — the visible gap

Done so far: the generator card is two rows, the generator column is data-driven, Gemini/Canva/Zoom/
Spotify are listed, and the refresh control is icon-only. **Not done, and the owner has flagged it
twice:**

1. **Refresh icon placement is wrong.** It was only shrunk in place, so it floats above the cards.
   It must sit **inline in each column's section header**, right-aligned — four in total across the
   two tabs, all calling the same `onRefreshApps`. See the placement note in 2b.
2. **Mappings rows still use the old compact layout** — small icon, inline buttons, and the
   **"Native app" subtitle that must be deleted** (it is the third row, same reasoning as
   "Installed"). Apply the 2-row card from section 2: 44–56pt icon spanning both rows, name + badge
   + gear on row 1, right-aligned buttons on row 2, `+ New Profile` omitted.
3. **Badges are not wired anywhere.** `DualAppGeneratorCard.setCompatibility(verified:)` exists and
   is never called. Feed it from the matched rule's `AppCompatibilityAssurance`.
4. **Assign Button does nothing for Canva/Zoom/Spotify** — they have no persisted mouse-button slot.
   Either add a generic per-target assignment store, or disable the button for targets whose
   `shortcutSlot` is nil.

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

**Thumb-wheel browser checklist:** the per-browser checkboxes must reflect what is actually
installed — grey out and disable any browser that is not present, rather than offering it. Detect by
bundle identifier through the same app scan the rest of the tab uses
(`com.google.Chrome`, `com.brave.Browser`, `com.microsoft.edgemac`, `com.vivaldi.Vivaldi`).
`ThumbWheelConfig`'s stored flags stay as they are; only the control's enabled state changes, so a
browser that is uninstalled and later reinstalled keeps its prior choice.

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
