# Gemini (native engine) profile isolation — implementation resume doc

Written 2026-07-25. **Implementation landed the same day — `./tools/check.sh` green**
(compiles under `-warnings-as-errors`, full suite passes). Everything in "Verified
facts" is proven on this machine, not inferred. Kept as the rationale record for the
rule, and for the vendor-update re-attestation still owed.

## Verified facts

Gemini.app 1.86.7.600, `com.google.GeminiMacOS`, team `EQHXZ8M8AV`.
Native AppKit/Swift — single ~165MB Mach-O, no Electron framework, no `app.asar`,
links only Apple frameworks. `codesign --verify --strict --deep` passes.
Entitlements: `app-sandbox = false`, `application-groups = group.com.google.common,
group.com.google.gemini`, `keychain-access-groups = EQHXZ8M8AV.com.google.GeminiMacOS`.
No `~/Library/Containers` entry.

**Isolation recipe (proven, 5 accounts, cold-start verified, vault-backed verified):**
```
CFFIXED_USER_HOME=<profileDir>          # redirects Application Support / HTTPStorages / Caches
ln -s ~/Library/Keychains <profileDir>/Library/Keychains   # REQUIRED
```

Why each piece:
- Plain `HOME` does **nothing** — macOS 26.x Foundation resolves `NSHomeDirectory()`
  from the password database and ignores `$HOME`. Verified with a Swift probe.
  `CFFIXED_USER_HOME` is the only knob.
- Without a reachable login keychain inside the redirected home, the app logs
  `signinStatus=waitingForKeychain` then
  `can_persist_config=0` → `"Not storing account config file, persistence disabled"`.
  Login works for the session and evaporates on quit. The symlink flips it to
  `can_persist_config=1` and writes `Data/user1/auth`.
- Gemini takes **no** profile/user-data flag. Its real flags include
  `--connected_folders=`, `--refresh_token=`, `--server_address=`,
  `--use_local_server`, `--skip_onboarding`, `--minichat`, `--trigger-key=`.
  `--user-data-dir=` is NOT implemented — the existing Electron path is inert here.

**Diagnosing:** `<profileDir>/Library/Caches/com.google.GeminiMacOS/Logs/diagnostic*.log`.
Grep `can_persist_config` (want 1), `StartNewOAuth` (0 on a restored cold start),
`new=0` (existing account recognised, not re-registered).

**Known residual leak:** `~/Library/Preferences/com.google.GeminiMacOS.plist` stays
shared — cfprefsd resolves the per-user domain and ignores `CFFIXED_USER_HOME`
(proven with a controlled UserDefaults probe). Feature flags, window frames and
`userN_*` keys are common across instances. Tolerable: each isolated profile names
its own account slot `user1`, so accounts do not collide.

**Rejected alternative:** rewriting `CFBundleIdentifier` on a copy of the app
(tested, works, and *does* get its own preferences domain — closing the leak above).
Rejected because: 238 MB per instance, ad-hoc signature drops `keychain-access-groups`
and the team ID, and Google's updater would fight a mismatched bundle id. Not shippable.

## Code changes required

Scope is smaller than first assumed:

1. **`Sources/Duplication/LauncherGenerator.swift:83`** — `allowedEnvironmentKeys`
   currently `{ "CODEX_HOME", "CODEX_ELECTRON_USER_DATA_PATH", "CLAUDE_CONFIG_DIR" }`,
   enforced at line ~620 (`disallowedEnvironmentKey`). Add `CFFIXED_USER_HOME`.

2. **`Sources/Duplication/EngineDetector.swift`** — add a field to
   `AppCompatibilityRule` for the keychain symlink (the launcher must create
   `<profileDir>/Library/Keychains -> ~/Library/Keychains`). There is no existing
   field for this; `homeSymlinkPrefix` is a different thing (visible `~/.claude-a`
   style link for multi-account CLI scanners).

3. **`Sources/Duplication/EngineDetector.swift`** — add the registry rule (see below).

4. **`Sources/Duplication/LauncherGenerator.swift`** — honour the new field when
   materialising a profile, and pre-create the `Library/{Application Support,
   HTTPStorages,Caches,Preferences}` skeleton.

**No change needed to `eligibility()`** — it consults
`registry.matchingRule(for:engine:)` *before* the `switch engine` fallback, so a
`.native` rule returns `.verified` already. `AppProfileEngine.native` and
`detect()` also already behave correctly. Do not add a native case to the switch.

### Draft rule

```swift
AppCompatibilityRule(
    id: "com-google-geminimacos-native-verified",
    bundleIdentifier: "com.google.GeminiMacOS",
    teamIdentifier: "EQHXZ8M8AV",
    engine: .native,
    testedVersions: ["1.86.7.600"],
    acceptsAnyVersion: true,
    requiredEnvironment: [
        "CFFIXED_USER_HOME": "{codexHomeDir}",   // or {profileDir} — see open question
    ],
    homeSymlinkPrefix: nil
    // + keychain-symlink field from change (2)
)
```

## Resolved during implementation

- **`{profileDir}`, not `{codexHomeDir}`.** For a native app the profile *is* the
  home, so pointing `CFFIXED_USER_HOME` at the sibling home would orphan every byte
  of Gemini data when the user deletes a profile. Verified the deletion paths use
  `FileManager.trashItem` / `removeItem`, which act on a symlink and never follow it,
  so the keychain link is safe inside the profile.
- **`HOME` is not needed.** Cold-started with `env -u HOME` and the login still
  restored (`StartNewOAuth` 0, `new=0`). The rule carries one key, and `HOME` stays
  off the allow-list.
- **`eligibility()` needed no change.** It consults the registry *before* the
  `switch engine` fallback, so a `.native` rule resolves without touching the
  unsupported branch.
- **Link target is correct in production.** `homeSymlinkRootURL` is constructed from
  `NSHomeDirectory()` at `Sources/KlikProApp.swift:3663`, so
  `<root>/Library/Keychains` is the real one; tests stay inside their sandbox root.

## Open questions

- **`{codexHomeDir}` vs `{profileDir}`** for `CFFIXED_USER_HOME`. `codexHomeDir` is
  the UUID-keyed sibling home under `CodexHomes/`, deliberately kept outside the
  profile-deletion path. Since the keychain symlink lives *inside* this directory,
  the sibling home is likely correct — but confirm deletion never follows symlinks
  (Foundation `removeItem` does not; a shell `rm -rf` on the dir also removes only
  the link, not the target — verify whatever Klik PRO actually uses, because a
  follow-symlinks delete would destroy the user's real `~/Library/Keychains`).
  **This is the one genuinely dangerous edge in this feature.**
- Whether `HOME` must be set alongside `CFFIXED_USER_HOME`. Being tested now; if
  `CFFIXED_USER_HOME` alone restores a login on cold start, keep the rule to one key
  and do not add `HOME` to the allowlist (allowlisting `HOME` is a broad hazard).

## Working artifacts already on disk

- `~/bin/gemini-profile <name>` — standalone shell launcher, creates + launches.
- `~/Applications/Klik PRO/Gemini Perfekta.app` — real bundle matching Klik PRO's
  emitted shape, reads the same `LaunchSpec.plist` contract, ad-hoc signed.
  Currently points at `~/Klik PRO Vault/Instances/GEMINI-PERFEKTA/gemini-home`.
- Profiles under `~/Library/Application Support/KlikPRO-GeminiProfiles/`
  (`test3`, `profile4`, `profile5`) plus the vault-backed `GEMINI-PERFEKTA`.

## Cleanup owed

Residue from the rejected bundle-id experiment:
`~/Library/{Application Support,Caches,HTTPStorages}/com.google.GeminiMacOS.klik2`,
`~/Library/Preferences/com.google.GeminiMacOS.klik2*.plist`, and a 238 MB re-signed
bundle under the session scratchpad `bundleid-test/`.

## NOT DONE — Gemini is not listed in the App Profiles UI

The catalogue rule makes Gemini *eligible*, but the generator UI is separately
curated, so nothing appears on screen yet. This is the remaining work before v1.4.6
is actually usable. Found 2026-07-25 after the release build; **do not publish v1.4.6
until this is resolved or the release notes are corrected.**

Two possible paths — check the cheap one first:

**A. It may already be reachable as an "alternative" (cheap, check first).**
`AppProfilesUI.swift:1374` builds `supportedCandidates = candidates.filter { $0.canCreate }`,
then `:1377` collects `alternatives` as every supported candidate that is *not* one of
the two hardcoded cards. If `AppProfileCandidate.canCreate` is true for
`.experimental` eligibility, Gemini should already be selectable through the
alternatives picker, and the only fix needed is wording/discoverability. **Verify what
`canCreate` returns for `.experimental` before writing any UI code.**

**B. A dedicated third generator card (expensive).**
`AppProfilesUI.swift` hardcodes exactly two: `chatGPTCard` / `claudeCard`, with ~40
reference points — declarations (`:1208-1209`), init (`:1249-1254`), layout origins
(`:1262-1263`, and `loadingView` height at `:1264` plus the `702` frame height at
`:1257`), 20 closure wirings (`:1309-1330`), the `addSubview` list (`:1331`), dock and
menu-bar state (`:1347-1370`), and the update/hide paths (`:1375-1402`).

Worse, every one of those closures dispatches an `AppProfileOriginalApp` case
(`.chatGPT` / `.claude`, defined in `KlikProConfig.swift:163-164`). Adding `.gemini`
cascades into all the original-app handlers in `KlikProApp.swift` — open, assign, dock
create/rename/change-icon/reset/delete, native dock add/remove, menu-bar toggle. Several
of those are Electron-shaped assumptions that need auditing for a native app rather than
copying blindly.

Recommendation: do A first. Only build B if the alternatives path genuinely cannot
surface Gemini, and treat the `AppProfileOriginalApp` expansion as its own reviewed
change rather than part of the card work.
