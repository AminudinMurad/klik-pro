# Klik PRO — Handover to the next Claude

_Last updated 2026-07-24. Read this top to bottom before touching the repo._

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
2. **Push/tag/publish only when the user explicitly says so.** Commit locally
   otherwise. Codex is the usual pusher; an explicit "release/push" authorizes that
   one action only.
3. **`tools/check.sh` must run un-sandboxed** — its preview-app launch stage fails in
   a sandbox with `kLSNoExecutableErr`. Same for `build-release.sh` /
   `render-previews.sh` (codesign + LaunchServices + Finder AppleScript for the DMG).

---

## 1. Current state

- **Preparing: v1.4.6 (build 23)** — Gemini App Profiles, on
  `feature/1.4.2-native-dock` (merged up to `main`, `./tools/check.sh` green). Not
  tagged or released yet.
- **Shipped: v1.4.5 (build 22)** — Latest GitHub release. `main` == `00c81db`.
  v1.4.4 and v1.4.5 shipped without refreshing this handover; corrected here.
- Prior shipped: **v1.4.1** (UI-only: bordered tab bar, `↻ Updates…`), **v1.4.2**
  (generator-card **Rename Dock Icon + Change Icon** for the native launcher, durable).
- **v1.4.3 contents:** the App Profile generator only force-adds Klik PRO's native
  "star" Dock launcher when **neither** the native tile nor the star launcher is
  already in the Dock (row hidden otherwise); a **Add Native App Dock Icon** gear item;
  the generator card tile now reflects a Rename/Change Icon (reverts on Reset); a
  per-profile **Add to Dock** gear item; and generation now appends all Dock tiles
  back-to-back before a **single `killall Dock`** so a tile can't be clobbered
  mid-relaunch (the "star bundle created but never pinned" bug).

- **On branch, unreleased — Gemini App Profiles** (`feature/1.4.2-native-dock`,
  `4127a30` + `7dbaba8`): the first `.native` catalogue entry,
  `com-google-geminimacos-native-untested`. Gemini exposes **no** profile flag, so
  isolation is `CFFIXED_USER_HOME={profileDir}` plus a `Library/Keychains` symlink the
  launcher provisions — without that link the app sets `can_persist_config=0` and
  silently drops the sign-in on quit. Plain `HOME` does nothing: Foundation resolves
  the home from the password database and ignores it. `AppCompatibilityRule` gained
  `requiresLoginKeychainLink` and `passesUserDataDirArgument`, and
  `specification(for:)` no longer hardcodes `--user-data-dir=` (it would have handed
  native apps a flag they don't implement). `eligibility()` needed no change.
  Rationale and evidence: `docs/gemini-native-isolation-resume.md`.
  **Owed before release:** the rule is `.untested`. A parked evidence instance at
  `~/Library/Application Support/Klik PRO Evidence/gemini-1.86.7.600/` needs a
  one-time sign-in, then the relaunch and post-update attestations (commands in its
  `README.md`) before it can be promoted to `.verified`. Do not claim Verified in
  release notes until both gates are recorded.

## 2. Next: v1.4.4 — UI optimization only

**No new features.** UI polish / optimization pass (scope to be defined with the user).

## 3. Cancelled / deferred

- **v1.5 `Original → Native` identifier rename: CANCELLED.** The old
  `wip/v1.5-generator-rename-changeicon` branch and its `docs/PLAN_v1.5.md` are
  deleted. Do not resurrect unless the user re-opens it.
- **Deferred hardening (latent, not an active bug):** the remove-then-re-add Dock
  flows — **Replace Dock Icon** (`createOriginalDockIcon`), **Rename Dock Icon**
  (`renameOriginalDockIcon`), **Change Icon / Reset** (`applyOriginalDockIconEdit`) —
  still do remove + re-add with 2–3 separate `killall Dock`. Same race class the v1.4.3
  generation fix solved, but masked today (single fixed path, UI trusts the operation
  result). If a tile ever flickers out there, apply the same pattern: a remove-from-
  prefs helper (no killall) + `appendLauncherToDockPrefs` (no killall) + one terminal
  `killall`. The write-only helper `appendLauncherToDockPrefs` already exists.

## 4. Branches

Working branch is **`feature/1.4.2-native-dock`** — the name is **stale** (we're past
1.4.2); development continued on it through 1.4.3. Releases are cut from **`main`**
(fast-forward `main` to the branch HEAD, tag there). Consider working directly on
`main` or a freshly-named branch for 1.4.4 — confirm with the user / coordinate with
Codex (who may hold local state) first.

## 5. Release checklist (how 1.4.1–1.4.3 shipped)

1. Run the **no-AI gate** (§0.1) on full history. STOP on any hit.
2. `check.sh` green (un-sandboxed).
3. Bump both plists (`App/Info.plist` + `App/KlikProHelper-Info.plist`, main == helper),
   commit `release: Klik PRO X.Y.Z build N`.
4. `./tools/build-release.sh` → DMG/ZIP/installer + `.sha256` (+ `.sha256.sig` when the
   release-signing key at `~/.config/klik-pro/release-signing/id_ed25519` is present) in
   `releases/` (git-ignored). Verify checksums.
5. Add `docs/RELEASE_NOTES_vX.Y.Z.md`; commit `docs: add vX.Y.Z release notes`.
6. Only when the user says so: FF `main` to HEAD, `git push origin HEAD:main`,
   `git tag -a vX.Y.Z <HEAD>`, push tag, `gh release create vX.Y.Z --notes-file …
   --latest <9 assets>`. Verify it's **Latest** with 9 assets.

_Local memory (persists across sessions) holds the durable rules:_
`no-ai-attribution`, `klik-pro-binary-feature-grep` (grep long selectors, not short UI
strings — Swift small-string opt), `check-sh-needs-unsandboxed`,
`klik-pro-v132-original-dock-launcher` (Codex pushes).
