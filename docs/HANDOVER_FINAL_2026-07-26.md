# Klik PRO — final handover, 2026-07-26

Read this first, then `docs/HANDOVER_v1.5.0.md` for the detail. Branch `release/v1.5.0`,
version **1.5.0 / build 23**. Working tree clean except the untracked
`Klik PRO - sample icons/` folder (predates this work, never part of it).

## Commits landed today

| Commit | What |
|---|---|
| `903bcce` | List-order pin — 3 pinned cards per list, all four card types, 3-row Mappings viewport |
| `46cbee2` | No default shortcut except Forward `⌘]` and Back `⌘[` |
| `889f506` | Docs: `COMPATIBILITY.md` is the app-list source of truth; two divergences recorded |

`tools/check.sh` was green (exit 0) at `46cbee2`. Run it **unsandboxed** — its preview stage
fails in a sandbox with `kLSNoExecutableErr`.

Verify check.sh's real result, never a pipeline's:

```bash
./tools/check.sh > /tmp/check.log 2>&1; echo "EXIT: $?"
```

A trailing `| tail` returns *tail's* exit code and will report success over a failing run.
That happened in this session and briefly hid a red suite.

## Owner decisions, with rationale

**Fresh install maps only Forward `⌘]` and Back `⌘[`.** Beyond the scroll wheel, the two side
buttons are the pair essentially every advanced mouse has, so they are the only controls that can
be assumed to exist. Middle, Gesture and the thumb wheel vary by model. Klik PRO is explicitly not
aimed at basic mice.

**Everything else ships with no shortcut at all**, not merely disabled — Middle, Gesture and all
three app hotkeys read **No shortcut**. Nothing is auto-pinned, no browser checkbox is pre-ticked,
no button is pre-assigned to an app.

**Pinning:** up to 3 per list, refuse the 4th rather than evict, nothing auto-pinned, pin control on
both tabs, Mappings viewport exactly 3 cards. Pinning reorders — nothing is hidden.

**Mouse profiles (spec only, not built):** up to 3, every profile exposes every control, two-step
activation via the existing carousel. See `HANDOVER_v1.5.0.md` §4e.

**`docs/COMPATIBILITY.md` is the source of truth for the badge.** Assurance in the registry is no
longer authoritative.

## THE ONE UNFINISHED TASK — badge vs COMPATIBILITY.md

`docs/COMPATIBILITY.md` lists every shipping app as **Verified** and its Unverified section reads
"None yet". The registry disagrees: six rules still carry `assurance: .untested` — ChatGPT, Gemini,
Antigravity, Antigravity IDE, Chrome, Brave. That is why ChatGPT and Gemini badge Unverified.

**I attempted this and reverted it.** Do not repeat my mistake. Changing the six rules is easy:

```
Sources/Duplication/EngineDetector.swift   assurance: .untested → .verified   (6 rules)
tools/check.sh:83                          the guard requiring `.untested` must go
```

The trap is the tests. Three assertions expect `.untested` and must be updated **individually**:

- `ChatGPT must stay honestly Untested while accepting vendor updates` — update to Verified
- `Gemini must stay honestly Untested until it survives a vendor update` — update to Verified
- `future ChatGPT versions must remain labelled Untested` — update to Verified

**But `engine detection alone must never grant Verified` must NOT change.** It asserts that an app
matched only by engine, with no rule, does not get Verified — that is correct and still wanted. A
blanket find-and-replace of `== .untested` breaks it. That is exactly what I did, which is why this
is unfinished rather than done.

Second divergence, owner has not ruled: COMPATIBILITY.md lists **Cursor, Discord, Notion, Obsidian,
Slack, Visual Studio Code** as Verified, but no rule ships for any of them and a rule is required for
an app to appear at all. Either add rules or move them to Pending.

## Rule ids are frozen — a stale instruction corrected

`HANDOVER_v1.5.0.md` §2 item 7 says to rename `com-openai-codex-untested` and
`com-google-geminimacos-native-untested` "now" because only Claude's id was persisted. **That check
was 2026-07-25 and is no longer true.** The live config shows `ChatGPT 1` and `Gemini 1` have claimed
both. Ids are re-validated at every launch, so renaming now breaks those profiles. It needs the
`previousIDs: [String]` migration. **Changing assurance is safe and separable** — assurance is not
part of an id and is not persisted per instance.

Lesson: never put assurance in a rule id again. The newer rules (`com-canva-canvadesktop`,
`com-spotify-client`) are assurance-neutral and can badge freely.

## Rules that will bite you

**Every combo comparison must check `isSet` first.** All unset combos share one `signature`, so an
unguarded comparison makes each blank row duplicate every other. Three guards exist, all
load-bearing — the worst is hotkey registration: the sentinel key code is rejected and that failure
path calls `exit(1)`, taking the input helper down. Detail in §4f.

**Conflict evaluation short-circuits disabled AND unset rows to `.ok`.** Any test fixture built from
`KlikProConfig.default` that expects a Duplicate/reserved/extension verdict must state its own
preconditions — set `enabled = true` *and* an explicit combo. Symptom is a cascade: fix one
assertion, the next fails identically. Seven fixtures needed this today.

To tell a failure of yours from a pre-existing one:

```bash
git show HEAD:Tests/MouseButtonRoutingTests.swift > /tmp/t.swift
```

...then compile against `git show HEAD:Sources/KlikProConfig.swift` and run.

**Do not bump `schemaVersion`** for an additive field. The write path pins the stored value to 12
and `check.sh` greps that literal, so a new `if schemaVersion < 13` gate would fire on every launch
forever. Mouse profiles is the first change that genuinely needs the pin lifted.

**No AI attribution in commits.** CI (`no-ai-coauthor-metadata.yml`) rejects Claude/Anthropic
co-author trailers and `<noreply@anthropic.com>` outright.

## Inspecting a fresh install without uninstalling anything

```bash
rm -rf /tmp/kf && open -n --env KLIK_PRO_CONFIG_DIRECTORY=/tmp/kf "/Applications/Klik PRO.app"
```

```bash
python3 -m json.tool /tmp/kf/config.json
```

Do not add `-W` — it waits for the app to *quit*, not to write. `PreviewMain` also accepts
`KLIK_PRO_PREVIEW_INSTALLED_TARGETS=all` now, added so the pin cap and >3-row scrolling can be
rendered at all.

## Device registration — feasibility proven

`IOHIDManager` (usage page 1 / usage 2) enumerated both of the owner's mice with unique serials:
Logi M650 `0x046D/0xB02A`, MX Master 3 Mac `0x046D/0xB023`. Scanning is ~40 lines, no new dependency.
**Filter out built-ins** — the same match also returns the internal trackpad and MX Keys Mac.

Per-event attribution is the hard part: `CGEvent` carries no reliable physical-device id, and the
CGEventTap is what suppresses the original click. **Recommended: switch the active profile on device
arrival/removal instead** — `installGestureServiceArrivalObserver` already does exactly this for one
hardcoded VID/PID. Detail in §4e.

## Known gaps, none blocking

- **The DMG in `releases/` is stale** — built 15:37, before the blank-shortcut work. Rebuild with
  `./tools/build-release.sh` before shipping. It overwrites 1.5.0/23 in place; two different binaries
  already share that version (a backup of the earlier one is not preserved outside this session).
- **No fixture renders a blank row or a pinned row**, so `No shortcut`, the hidden Reset/badge, and
  the disabled at-limit pin are unverified in pixels.
- **A fresh install auto-creates 7 App Profiles** (`Canva 1`, `Spotify 1`, `Gemini 1` + others).
  Pre-existing, arguably contradicts "starts quiet", owner never ruled.
- **The showcase GIF eyebrow still reads "KLIK PRO 1.2.2"** — pre-existing, left alone deliberately.
- **`render-app-profiles-showcase.swift` crop is top-left origin** (`sourceRect` flips it). Easy to
  get backwards; nothing verifies the framing, so eyeball the GIF after any list-geometry change.
