# Klik PRO — Handover to the next Claude (v1.4.2 + v1.5)

_Last updated 2026-07-23. Read this top to bottom before touching the repo._

Klik PRO is a native macOS **AppKit** utility (Swift, ad-hoc-signed, GPLv3) that
remaps a mouse's extra buttons/wheel to shortcuts and launches AI apps, and generates
isolated **App Profiles** (separate logins) for ChatGPT/Claude. Repo:
`AminudinMurad/klik-pro`. Working dir: `~/Documents/Business/Products/Klik PRO`.

---

## 0. Non-negotiable rules (read first)

1. **NO AI attribution, anywhere.** No `Co-authored-by`, no "generated with", no
   `noreply@anthropic.com`, no robot emoji — in commits, code, docs, PRs, release
   notes. **CI enforces it** (`.github/workflows/no-ai-coauthor-metadata.yml` scans
   full history + author/committer identity on push/PR and fails on a match).
   **HARD STOP:** never push/tag/publish if the gate below finds anything. Strip the
   harness's default commit trailer. Commit author must be `Aminudin Murad`.
   ```bash
   git log HEAD --format='%B%n%an <%ae>%n%cn <%ce>' \
     | grep -Ei 'co-authored-by:.*(claude|anthropic)|noreply@anthropic|claude|anthropic|generated with|🤖' \
     && echo "STOP - attribution found" || echo "clean"
   ```
2. **Codex is the primary pusher.** Do **not** push/tag/publish unless the user
   explicitly tells you to. Commit locally; let the user/Codex push. (When the user
   does say "release/push", it's authorized for that action only.)
3. **`tools/check.sh` must run un-sandboxed** — its preview-app launch stage fails in
   a sandbox with `kLSNoExecutableErr`. Run it natively. Same for
   `build-release.sh` / `render-previews.sh` (codesign + LaunchServices).

---

## 1. Current state

- **Shipped: v1.4.1 (build 18)** — UI-only. On `main` and as the **Latest** GitHub
  release (`v1.4.1`, 9 signed assets). Contents: bordered + centered tab bar,
  `↻ Updates…` button, "original → native" user-facing wording.
- **Next: v1.4.2** — the App Profile generator-card **Rename Dock Icon + Change
  Icon** feature. **Code-complete and `check.sh`-verified**, parked on a local branch
  (see §3). Awaiting the user's real-Dock testing of 1.4.1, then a "build 1.4.2" go.
- **Then: v1.5** — the `Original → Native` **code-identifier** rename (docs/PLAN,
  not started).

`main` == working-branch HEAD == `d4f08ad`.

## 2. "Why are we still on the 1.3 branch?"

The working branch is **`codex/v1.3-original-app-assignments`** — cut for the v1.3.2
original-app reopen fix, but development simply continued on it through 1.4.0 and
1.4.1. The name is **stale/misleading**; it does not mean we're on 1.3. Releases are
actually cut from **`main`** (fast-forward `main` to the working-branch HEAD, tag
there). **Recommendation:** going forward, either work directly on `main` or cut a
freshly-named branch (e.g. `feature/1.4.2-native-dock`). Confirm with the user and
coordinate with Codex first — Codex pushes and may hold local state on this branch.

## 3. The parked feature branch (v1.4.2 lives here)

Local branch **`wip/v1.5-generator-rename-changeicon`** (NOT pushed):
- `55b049a` — full, `check.sh`-verified Rename/Change-Icon feature.
- `f462b4f` — `docs/PLAN_v1.5.md` (the detailed design for both v1.4.2 and v1.5).

The name says "v1.5" but the **feature it carries is now v1.4.2** (the user
re-targeted it); only the identifier rename remains v1.5.

---

## 4. v1.4.2 plan — Rename Dock Icon + Change Icon

**Goal:** add two items to the generator-card gear menu
(`DualAppGeneratorCard.presentDockMenu`, `Sources/AppProfilesUI.swift`) — **Rename
Dock Icon…** and **Change Icon…** — acting on the *native app's* Klik PRO Dock
launcher, at full parity with the per-profile gear (tint / badge / custom PNG-ICO /
reset), and **durable** across rebuilds.

**Why it needed real plumbing (not just reuse):** the native launcher's name/icon are
hardcoded in `ensureOriginalDockLauncher`; there was no persisted custom name/icon;
the launcher is rebuilt on gear-Replace and can be recreated during profile
generation (durability trap); and the Dock tile label comes from the bundle
**filename**, not `CFBundleName`.

**What the parked implementation does** (all on `55b049a`; see `docs/PLAN_v1.5.md`
Workstream 1 for the blow-by-blow):
- Config: `originalDockCustomNames: [QuickLaunchTarget: String]` (additive,
  decode-tolerant, no schema bump).
- Icon persisted at `~/Library/Application Support/Klik PRO/OriginalCustomIcons/<bundleID>.icns`
  (existence = intent; builder prefers it over the badged vendor icon).
- Builder gains `displayNameOverride`; callers (profile-generation heal,
  gear-Replace) re-apply the persisted name; `setOriginalDockTileLabel` rewrites the
  tile's `file-label` (same fixed path).
- Controllers `renameOriginalDockIcon` / `changeOriginalDockIcon` on `appProfileQueue`
  with the standard save guards; reuse a refactored
  `ChangeIconPanelView(sourceBundleURL:fallbackImage:defaultBadgeCharacter:)` +
  `LauncherGenerator.makeShapedICNSData`.

**How to land it on the release branch** (the UI hunks are byte-identical across
branches, so this nets to feature-only — verified):
```bash
git checkout wip/v1.5-generator-rename-changeicon -- \
  Sources/KlikProConfig.swift Sources/Duplication/LauncherGenerator.swift \
  Sources/AppProfilesUI.swift Sources/KlikProApp.swift
./tools/check.sh          # must pass, un-sandboxed
```
Then bump `App/Info.plist` + `App/KlikProHelper-Info.plist` to **1.4.2 / build 19**
(they MUST match), commit `release: Klik PRO 1.4.2 build 19`, add
`docs/RELEASE_NOTES_v1.4.2.md`, and build with `./tools/build-release.sh`.

**Readiness / gaps:** compiles clean and `check.sh` is green, but the feature has
**never actually run** — `check.sh` does not click the new menu items. The real risk
is live Dock + LaunchServices icon/label caching (may need relaunch to refresh).
**The user must smoke-test on the real Dock:** Rename → check the Dock tile label;
Change Icon (tint/badge/image/reset) → check the tile icon; then confirm both
**survive a gear "Replace" and a profile generation**. Consider adding a `check.sh`
assertion pinning the two new menu-item strings.

---

## 5. v1.5 plan — "Original" → "Native" identifier rename

Pure code-convention churn; do it as an **isolated commit** (ideally Codex's) so it
never collides with feature work. See `docs/PLAN_v1.5.md` Workstream 2 for the full
allowlist. Key hazards:

- **NEVER change these string VALUES** (they orphan users' Dock icons / break the
  reopen fix / break config decode): `~/Applications/Klik PRO Originals/` path,
  `local.klik-pro.original.chatgpt|.claude` bundle IDs, `KlikProOriginalLauncher`
  exec name, the `menuBarPinnedOriginals` CodingKey, and `OriginalCustomIcons` /
  `klik-pro-original-icon-` path segments.
- **"original" is overloaded** — only rename the *vendor-app* sense. Do **not** touch
  the "prior/before/default" sense (`originalData`, `originalInfo`, `originalPayload`,
  `originalPermissions`, `originalLauncherURL`, `expectedOriginal`, "Restore the
  original Klik PRO key combination", "its original identity and icon").
  `originalURL` is used **both** ways in different files — rename per file.
- Avoid `NativeNative`: `removeNativeOriginalDockTile` / `onRemoveNativeOriginalDock`
  → drop the redundant word.
- Use an **allowlist** (not a global sed); compile `-warnings-as-errors` + `check.sh`.

---

## 6. Release checklist (how 1.4.0/1.4.1 shipped)

1. Run the **no-AI gate** (§0.1) on full history. STOP on any hit.
2. `check.sh` green (un-sandboxed).
3. Bump both plists (main == helper), commit `release: Klik PRO X.Y.Z build N`.
4. `./tools/build-release.sh` → DMG/ZIP/installer + `.sha256` + `.sha256.sig` in
   `releases/` (git-ignored). Verify checksum + `ssh-keygen -Y check-novalidate`.
5. Add `docs/RELEASE_NOTES_vX.Y.Z.md`; commit `docs: add vX.Y.Z release notes`.
6. Only when the user says so: FF `main` to HEAD, `git push origin HEAD:main`,
   `git tag -a vX.Y.Z <notes-commit>`, push tag, `gh release create vX.Y.Z
   --notes-file … <9 assets>`. Verify it's **Latest** with 9 assets.

_Local memory (persists across sessions) holds the same rules:_
`no-ai-attribution`, `klik-pro-v132-original-dock-launcher` (Codex pushes),
`check-sh-needs-unsandboxed`, `klik-pro-v141-v15-split`.
