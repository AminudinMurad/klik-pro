# App Profiles — Data & Maintenance — design spec (v1.2.1)

**Status:** design-only, for review. **No implementation, commit, push, tag, or
release** until Aminudin approves and Codex-A signs off.
**Target:** v1.2.1. (Exact version metadata / build number is **not** promised
here — it will be set when the implementation branch stamps `Info.plist`.)
**Implementation base:** `origin/main` **`954540d`** (exact released v1.2.0), in
worktree `worktrees/codex-a-v1.2.1-data-maintenance` on branch
`codex/v1.2.1-data-maintenance`. Baseline `./tools/check.sh` green at
`build/check-20260722-014354`. **All line references below are against `954540d`.**
**Supersedes:** the earlier narrower "orphan cleanup" draft (this file); that
scope is folded in as Phase B.

### Revision — Codex-A round 1 (all 8 points addressed)
1. **Archived enforcement across every runtime consumer** — new §6.6 enumerates
   each consumer with `954540d` refs; assignments preserved for losslessness,
   runtime-ineligible while archived; Restore revalidates conflicts (§6.2).
2. **Durable recovery / manifest completeness** — §4 redefines manifest v2 fields
   + a **vault-owned** durable custom-icon asset; iconPath is never recovery
   truth; migration/fallback for existing vault profiles.
3. **Archive transaction + I4** — §6.1 gives the precise ordered transaction; I4
   is now an **eventual-repair** invariant (startup reconciliation repairs the
   manifest); no claim of cross-file atomicity.
4. **Icon-preserving staged removal** — §6.1 + §11 define and test an
   archive-specific launcher removal distinct from permanent cleanup (which
   deletes the icon at `LauncherGenerator.swift:1323`).
5. **Auto-refresh** — §7 recomputes the full inventory and refreshes **both** the
   App Profiles cards and the Data & Maintenance list, not only the health dict.
6. **Trash test injection + partial results** — §6.5 + §11 inject the trash
   op/temp destination (never the real Trash) and define partial-result reporting.
7. **Base/worktree corrected** — header above (`954540d`, not `curated-app-profiles`).
8. **Line refs rechecked against `954540d`; "build 5" promise removed.**

### Revision — owner override + Phase B implementation (2026-07-22)
Authorized by Aminudin (plan approval this session). Records where the built
Phase B intentionally departs from the text above; **pending Codex-A review**.
1. **Permanent delete is now a user-chosen mode** alongside Move to Trash. The
   delete confirmation offers **Move to Trash** (default, recoverable) **and**
   **Delete Permanently**. This deliberately overrides **I1** ("data is sacred —
   Trash only") and the §13 non-goal "No permanent deletion anywhere." Both
   modes share the identical ownership/path gates, exclusive lock, two-pass
   process scan (for record-bearing targets), and the non-overlapping artifact
   plan; only the final op differs (`trashItem` vs `removeItem`), via
   `LauncherGenerator.removeOwnedArtifact(…, mode:)`.
2. **Direct delete on visible rows.** Healthy / Archived / Missing-Launcher rows
   expose a **Delete…** action (not only orphans), because the reported need was
   "delete a profile I can see." Missing-Data rows keep **Forget…** only.
3. **Classification shipped as 4 states in Phase A**; Phase B adds
   `orphanedData` / `needsManualReview` as **scan findings** (`OrphanFinding`
   from `scanOrphans`), surfaced in their own maintenance group — not as
   `maintenanceHealth(for:)` cases (that call is per config record).
4. **Orphan in-use gate.** A record-less orphan has no source app, so the
   two-pass argv scan cannot run for it; its fail-closed in-use protection is the
   **exclusive per-instance lock** (a running managed launcher holds the shared
   lock). Record-bearing deletes still run the full two-pass scan. Listing a
   running orphan is harmless — `reclaimData` refuses it at the lock.

### Revision — Codex-A round 2 (conditional approval; 4 final corrections)
1. **Archive crash consistency** — §6.1 reordered: **persist archived config first
   (commit point), no filesystem artifact touched before it**; then manifest; then
   stage + icon-preserving launcher removal; then references. Crash-after-persist →
   reconciliation completes removal; persist-fail → disk untouched. Legacy stale
   staging-path sweep documented separately.
2. **Non-overlapping trash plan** — §6.5: trash the vault `Instances/<UUID>`
   container once (not container + children); AS lists only independent roots;
   dedupe + reject ancestor/descendant overlap before any move.
3. **Shared pure conflict evaluator** — §6.2: Restore uses an extracted AppKit-free
   `appProfileAssignmentConflicts(candidate:against:)` shared by UI and
   manager/runtime; manager not coupled to view-controller helpers.
4. **I9 narrowed** — fail-closed scan/lock applies only to ops that inspect/move
   profile data; Archive/Repair/Restore are data-read-only (no scan/lock).

---

## 1. Problem

Manually deleting a generated launcher (e.g. `~/Applications/Klik PRO/ChatGPT T.app`)
leaves a **stale App Profiles record**: the card still lists the profile (managed
rows short-circuit the visibility filter — `instance.launcherKind == .managed || … ||
FileManager.default.fileExists(launcherPath)`,
[`AppProfilesUI.swift:863`](../Sources/AppProfilesUI.swift)), but its launcher is
gone. **Open fails** (`generatedLauncherURL`, used at
[`KlikProApp.swift:4593`](../Sources/KlikProApp.swift), throws `launcherUnavailable`),
health is computed but **never shown on the card**, and there is **no repair
path** — the row just sits there broken.

The current "Remove" is ambiguous and, for vault profiles, **loses the recovery
record it claims to keep**:

- `AppProfileManager.remove(deleteProfileData: false)`
  ([`AppProfileManager.swift:462`](../Sources/Duplication/AppProfileManager.swift))
  deletes the launcher **and the config row**, retaining profile data "for
  recovery" (alert at [`KlikProApp.swift:4536`](../Sources/KlikProApp.swift)).
- It then calls `updateVaultManifest(config: updated)`
  ([`AppProfileManager.swift:882`](../Sources/Duplication/AppProfileManager.swift)),
  which **rebuilds `vault.json` from the surviving `config.instances`** — dropping
  the removed profile's record. `adoptVault`
  ([`AppProfileManager.swift:731`](../Sources/Duplication/AppProfileManager.swift))
  restores only what the manifest lists, so retained data becomes **orphaned and
  unrecoverable as a profile.**

Health is computed (`AppProfileRuntimeHealth`,
[`AppProfileRuntime.swift:230`](../Sources/Duplication/AppProfileRuntime.swift);
`refreshAppProfileHealth()`, [`KlikProApp.swift:4628`](../Sources/KlikProApp.swift))
and threaded into the cards as a `health:` parameter
([`AppProfilesUI.swift:357`](../Sources/AppProfilesUI.swift),
[`:521`](../Sources/AppProfilesUI.swift)) — but **never rendered**. A refresh hook
exists on app activation (`NSApplication.didBecomeActiveNotification`,
[`KlikProApp.swift:2901`](../Sources/KlikProApp.swift)), but it only refreshes the
runtime-health dictionary.

---

## 2. Source-of-truth precedence

When the three stores disagree, resolve in this order:

1. **`config.json` record** (`KlikProConfig.instances`) — the single authority for
   a profile's **existence, lifecycle state, recipe, metadata, assignments, and
   data location**. Identity is the UUID. The everyday path never silently deletes
   a row.
2. **`vault.json` manifest** — the authority for **vault recovery** after a
   reinstall/re-adopt. A **derived mirror** of config's vault-stored, data-bearing
   records; may briefly lag and is repaired by reconciliation (§I4).
3. **Filesystem artifacts** — launcher bundle, profile data + `.klik-pro-owned-profile`
   marker ([`KlikProManagedLauncher.swift:242`](../Sources/KlikProManagedLauncher.swift)),
   `CodexHomes/<UUID>`, custom-icon asset, `~/.claude-*`/`~/.codex-*` symlinks.
   **Derived**, reconciled against (1)/(2); the marker is the ownership proof for
   destructive data ops.

**Machine-specific paths are never recovery truth.** `AppProfileInstance.iconPath`
and `launcherPath` are machine-local working values, re-derived on this machine;
recovery relies only on the manifest + vault-owned assets (§4).

**Conflict rules:** record present + artifact missing → a health state (Repair or
Forget), never silent disappearance. Artifact present + no trustworthy record →
Orphaned Data (never auto-adopt without a recipe, §5). config vs manifest disagree
→ config wins; reconciliation repairs the manifest, never the reverse.

---

## 3. Invariants

- **I1 — Data is sacred.** ⚠️ **Superseded in part by the 2026-07-22 owner
  override:** Move to Trash remains the default and recommended path, but a
  user-chosen **Delete Permanently** mode now also exists. Both modes are
  marker-gated, exclusive-lock + fail-closed process-scan protected; the
  reversibility guarantee holds only for the Trash mode.
- **I2 — UUID identity is stable.** Never reused or regenerated; Repair/Restore/
  Archive act on the same UUID.
- **I3 — Archive is lossless & reversible.** Full record, recipe, metadata, and
  **assignments** preserved; Restore reproduces the launcher from the recipe.
- **I4 — Eventual manifest consistency (NOT cross-file atomicity).** `config.json`
  is authoritative; `vault.json` is a derived mirror that may lag. A manifest
  write failure is a **surfaced, non-fatal lag** — config stays correct, and the
  next reconciliation (startup, or any archive/restore/forget) rewrites the
  manifest to mirror config's vault-stored, data-bearing records. We do **not**
  claim atomic config+manifest writes.
- **I5 — Reconciliation & repair are data-read-only.** Scan, classify, Repair
  Launcher, and Restore never create, move, or modify profile data.
- **I6 — Ownership proof before destruction.** Destructive data actions require
  the marker + standardized-path + symlink-rejection checks; markerless candidates
  are manual-review only.
- **I7 — Surgical reference cleanup.** Dock/menu removal touches **only** the
  exact, resolved-path-verified Klik-PRO-owned entry for that UUID's launcher;
  unrelated Dock entries are never rewritten. Unverifiable cleanup → the primary
  op still succeeds; the leftover reference is surfaced with a manual-remediation
  note.
- **I8 — No silent re-pin.** Restore never re-adds a Dock entry and never
  auto-enables the menu-bar pin; the user re-pins explicitly.
- **I9 — Fail closed (scoped to data-inspecting/moving ops).** The exclusive-lock
  + fail-closed process-scan requirements apply to operations that **inspect or
  move profile data** — Move to Trash (and any future delete-with-data path). An
  incomplete scan, unacquirable lock, failed ownership check, or unverifiable path
  aborts those with no change. **Archive, Repair, and Restore are data-read-only
  and do NOT require a process scan or exclusive lock** (they never touch profile
  data); they still fail closed on ownership/path/recipe checks and on regeneration
  errors.

---

## 4. Data model, manifest, and durable recovery (schema 11 → 12)

**Config (additive; every v1.2.0 row decodes unchanged).**
```
enum AppProfileState: String, Codable { case active, archived }
AppProfileInstance:
  + var state: AppProfileState   // decodeIfPresent ?? .active
  + var archivedAt: Date?        // display only
```
Schema 11 → 12 mirrors the additive 10 → 11 pattern
([`AppProfileInstance.swift`](../Sources/Duplication/AppProfileInstance.swift)):
version bump + defaulting, no row re-keyed, no data moved. `hotkey` and
`mouseButton` (core assignments) are **preserved** on archive; `pinToMenuBar` is a
menu-bar display toggle and is cleared on archive (§6.1) — it is not a core
assignment, so clearing it also satisfies I8.

**Manifest v2 — a *complete* recovery recipe (Codex-A #2).**
Current `VaultManifestInstanceRecord`
([`VaultDataRoot.swift:107`](../Sources/Duplication/VaultDataRoot.swift)) omits
lifecycle and icon state, and the custom icon lives outside the vault
(`CustomIcons/<UUID>.icns` in Application Support), so a reinstall can't restore
the exact icon. Manifest schema 1 → 2 adds portable, machine-independent fields:
```
VaultManifestInstanceRecord (v2):
  + var archived: Bool          // decodeIfPresent ?? false  (mirror of state)
  + var menuColor: String?      // AppProfileMenuColor raw value
  + var customIcon: Bool        // true ⇒ a vault-owned icon asset exists
```
- **Durable custom-icon asset (vault-owned):** for `.vault` instances the exact
  custom icon is stored at **`<Vault>/Instances/<UUID>/custom-icon.icns`** (beside
  `user-data`/`config-home`), so it travels with the vault. `customIcon: true`
  means "read that asset on adopt and stamp it." The Application-Support
  `CustomIcons/<UUID>.icns` ([`LauncherGenerator.swift:895`](../Sources/Duplication/LauncherGenerator.swift))
  stays as the working/render copy and the store for `.applicationSupport`
  instances; it is **never** the recovery source for vault instances, and its
  absolute path is **never** persisted as recovery truth.
- **Adopt:** `adoptVault` re-derives the machine-local `iconPath` from the
  regenerated launcher; if `customIcon`, it copies the vault-owned asset into place
  and stamps it. `menuColor` restores the tint/badge recipe.
- **Migration / fallback for existing vault profiles (manifest v1, no vault-owned
  icon):** on the first v1.2.1 heal/adopt, if a `.vault` instance has an
  Application-Support `CustomIcons/<UUID>.icns`, copy it to
  `<Vault>/Instances/<UUID>/custom-icon.icns` and set `customIcon: true`. If
  neither exists, recovery falls back to the **source app icon** (explicitly
  narrower — stated in the UI). `.applicationSupport` instances are unaffected
  (their icon store is already local and non-durable by definition).
- **`updateVaultManifest` #6 fix** ([`:882`](../Sources/Duplication/AppProfileManager.swift)):
  build records from every vault-stored, managed, marker-owned instance **regardless
  of `state`** (drop the implicit active-only filter), stamping `archived`,
  `menuColor`, and `customIcon`. Because Archive keeps the row (§6.1), the record
  is present to serialize; the manifest can no longer exclude a recoverable profile.
- Manifest `read` already accepts `1...currentSchemaVersion`
  ([`:141`](../Sources/Duplication/VaultDataRoot.swift)); bump `currentSchemaVersion`
  to 2, new fields `decodeIfPresent`-defaulted so v1 manifests still load.

---

## 5. Health states & evidence-aware classification (Codex-A #2)

Reconciliation is **computed** (never stored) by comparing each record to its
artifacts, plus a bounded scan of the Klik PRO roots
([`LauncherGenerator.swift` — `applicationSupportURL`/`visibleLaunchersRootURL:73`](../Sources/Duplication/LauncherGenerator.swift))
for marker-owned data with no record. Launcher validity via `validatedLauncherURL`,
data validity via owned-profile validation + marker.

| State | Evidence | Data | Launcher | Action |
|---|---|---|---|---|
| **Healthy** | record active, recipe valid | ✓ +marker | ✓ | (normal use) |
| **Recoverable Archived** | record `state=archived`, recipe present | ✓ kept | — (removed) | **Restore** |
| **Missing Launcher** | record active, recipe present | ✓ +marker | ✗ | **Repair Launcher** |
| **Missing Data** | record present | ✗ (gone/relocated) | any | **Forget Entry** |
| **Orphaned Data** | **no** trustworthy record; marker present | ✓ marker-owned | — | **Move to Trash** (+ inspect/export) |
| **Needs Manual Review** | UUID dir, **no marker** | markerless | — | none (path only) |

**Evidence-aware recovery (Decision 2):** a **trustworthy record with the complete
recipe** — from `config.json`, or from a `vault.json` v2 record (source, rule,
label, menuColor, customIcon) — is **Recoverable Archived** / **Missing Launcher**
→ Restore / Repair. A **marker-only folder with no recipe** is **Orphaned Data**:
we **do not reconstruct** (the marker holds only the UUID); we show inspect/export
details and **Move to Trash only**. **Markerless** folders are **Needs Manual
Review** — surfaced path, no Klik PRO delete.

Orphan qualification (all): well-formed UUID under a root; not in `config.instances`;
not in the running helper's active set (fail-closed on incomplete); not in a
current `vault.json`; marker present (else Needs Manual Review).

---

## 6. State transitions — behaviour, idempotency, rollback

```
                       Archive
    ┌───────────┐  ───────────────►  ┌──────────────────────┐
    │  Healthy  │                     │ Recoverable Archived │
    │ (active)  │  ◄───────────────   │   (state=archived)    │
    └───────────┘  Restore (revalidate└──────────────────────┘
      │      ▲     conflicts first)             │
 manual│     │Repair                            │ data deleted
 delete│     │Launcher                          │ from under it
launcher│    │                                   ▼
      ▼      │                            ┌──────────────┐
 ┌────────────────┐     data gone         │ Missing Data │
 │ Missing Launcher├──────────────────────►│              │
 └────────────────┘                       └──────────────┘
                                                 │ Forget Entry
   Orphaned Data ──Move to Trash──► (→ Trash)     ▼ (record+manifest removed;
   (marker, no recipe)                              user data untouched)
   Needs Manual Review (no marker) ── surfaced only
```

### 6.1 Archive (Active → Recoverable Archived) — precise transaction (Codex-A #3, #4)

Archive is **data-read-only**, so it takes **no exclusive lock and no process
scan** (removing the launcher bundle does not affect a running target app, which is
a separate process — see I9). **Config persist is the commit point, and NO
filesystem artifact is touched before it** (Codex-A round 2 #1): if persist fails,
the disk is untouched; if the process crashes *after* persist, startup
reconciliation sees `archived` + an existing launcher and finishes the job. Ordered
transaction:

1. **Build + persist archived config** — set `state=.archived`, `archivedAt=now`,
   `pinToMenuBar=false`; **keep** `hotkey`, `mouseButton`, `menuColor`, `iconPath`,
   `profileDirectory`, recipe. Persist. **If persist fails → abort; no filesystem
   artifact was touched; record stays active** (the only rollback boundary).
2. **Reconcile manifest** — best-effort (I4). Failure = surfaced lag; config is
   already authoritative.
3. **Stage + icon-preserving commit of launcher removal.** `stageLauncherRemoval`
   ([`:1288`](../Sources/Duplication/LauncherGenerator.swift)) moves the launcher to
   a hidden staging path, then commit deletes the staged bundle but **keeps the
   custom-icon asset**. The existing `commitLauncherRemoval`
   ([`:1311`](../Sources/Duplication/LauncherGenerator.swift)) **also deletes
   `CustomIcons/<UUID>.icns`** ([`:1323`](../Sources/Duplication/LauncherGenerator.swift)) —
   wrong for Archive. **Add a distinct `commitLauncherRemoval(preserveCustomIcon:)`
   (or an `archiveLauncher` primitive)** used only by Archive; the permanent path
   (Forget/Trash) keeps today's icon-dropping behaviour. This step is forward-only:
   because config already says archived, a failure here is not rolled back — it is
   completed by reconciliation (below).
4. **Best-effort reference/symlink cleanup (I7)** — after the launcher is gone:
   - **Dock:** remove **only** the persistent-apps entry whose resolved
     `_CFURLString` equals this launcher path (exact resolved-path match; never
     rewrite others). If Dock prefs can't be read/written → skip, record a
     manual-remediation note; do **not** roll back the archive.
   - **Home symlinks:** `removeHomeSymlinks(for:storage:)` (destination-verified,
     symlink-only). Menu-bar exclusion is automatic (§6.6).

- **Idempotency:** already-archived → no-op after step 1's state check; a re-run
  re-attempts only the forward steps whose artifacts still exist.
- **Crash recovery:** a crash after step 1 leaves `archived` + a present launcher
  (and/or a stale manifest / un-cleaned references). **Startup reconciliation**
  detects `state == .archived` with a still-present launcher and completes the
  icon-preserving removal, repairs the manifest (I4), and re-surfaces any
  un-cleaned Dock reference. This is safe because step 1 is authoritative and every
  later step is idempotent + forward-only.
- **Legacy stale staging paths (documented separately):** `stageLauncherRemoval`
  leaves a hidden `.<UUID>-…-removing-…` bundle if a commit was interrupted.
  Reconciliation **also** performs an independent, idempotent sweep of such
  Klik-PRO-owned staging remnants under the Launchers root (UUID-scoped,
  marker/name-verified, symlink-rejecting) and removes them — decoupled from any
  single Archive so an old interrupted removal never lingers.

### 6.2 Restore (Recoverable Archived → Healthy) — conflict revalidation (Codex-A #1)

1. **Revalidate conflicts first** (cheap, no filesystem) via a **shared, pure
   conflict evaluator** — NOT the view-controller helpers (Codex-A round 2 #3).
   Phase A extracts the current conflict rules (duplicate hotkey, duplicate mouse
   button, reserved Command-Tab — today entangled in view-controller code around
   `recomputeConflictBadges` [`:2899`](../Sources/KlikProApp.swift) and
   `ShortcutConflictStatus`) into a **pure function with no AppKit / no
   view-controller dependency**, e.g.
   `func appProfileAssignmentConflicts(candidate: AppProfileInstance, against activeInstances: [AppProfileInstance]) -> [AssignmentConflict]`.
   Both the UI (conflict badges) and the manager/runtime (this Restore check) call
   the **same** evaluator; the manager is never coupled to the view controller.
   Evaluate the record's `hotkey`/`mouseButton` against the **currently-active**
   instances only (archived excluded, §6.6). **On conflict: stay archived; explain
   exactly what conflicts and what to change** (e.g. "hotkey ⌃A is used by Claude P").
2. Re-inspect the source app + rule (must be Verified). Unavailable → Restore
   blocked with a reason; stays archived.
3. `regenerateLauncher(instance:sourceApp:)`
   ([`:665`](../Sources/Duplication/LauncherGenerator.swift)) — rebuilds **only**
   the launcher; re-applies the preserved custom icon; **never touches data**.
4. Recreate the home symlink (rule-gated); set `state=.active`, clear `archivedAt`;
   persist; reconcile manifest.
5. **No silent re-pin (I8):** `hotkey` + `mouseButton` reactivate (they were
   revalidated in step 1 — this is lossless restore). The **Dock entry is not
   re-added** and the **menu-bar pin stays off** (`pinToMenuBar` was cleared at
   archive); the user re-pins explicitly.

- **Idempotency:** already-active → no-op; `regenerateLauncher` refuses if a
  launcher already exists, so partial re-runs are safe.
- **Rollback boundary:** launcher rebuilt but persist fails → remove the fresh
  launcher, stay archived (no half-restored record).

### 6.3 Repair Launcher (Missing Launcher → Healthy)

Same mechanism as Restore step 3 (`regenerateLauncher` — launcher absent + owned
profile present is exactly this state). Blocked with a reason if the source app is
missing/unverified. **Never** writes profile data (I5). Launcher build is atomic
(temp bundle → move → register, [`buildLauncherBundle:701`](../Sources/Duplication/LauncherGenerator.swift));
failure leaves no partial launcher. Idempotent.

### 6.4 Forget Entry (record removal, no user-data deletion) — destructive-lite

Removes the config row **and** its manifest record; **touches no user data** (any
remaining Klik-owned launcher bundle for that UUID is also removed — a launcher is
not user data). Gated to **Missing Data** or explicitly stale records. Shows an
impact summary (what the record was; that data is *not* deleted; any data path
that becomes Orphaned Data). Confirmation required. Idempotent (absent → no-op).
Commit point is the config persist; the manifest update follows (surfaced no-op on
failure — record already gone from config).

### 6.5 Move Data to Trash (Orphaned Data / reclaim) — destructive (Codex-A #6)

The only data-removal path. Uses an **injectable trash operation** (production:
`FileManager.trashItem`; tests: a fake/temp destination — never the real Trash).
**Never** `removeItem`/permanent delete.

Pre-conditions (all, I6/I9): marker present; standardized in-root path; not a
symlink escaping the roots; **exclusive** `ManagedInstanceLock`; **two-pass**
`processInspector.profileReferences` fail-closed (mirrors
[`:512`](../Sources/Duplication/AppProfileManager.swift)). Shows the planned paths
+ total size; explicit confirm.

- **Artifact plan — non-overlapping owned roots (Codex-A round 2 #2):** build the
  move set, then **deduplicate and reject any ancestor/descendant overlap** before
  a single move:
  - **Vault instance:** trash the **owned `<Vault>/Instances/<UUID>` container
    exactly once** — never the container *and* its `user-data` / `config-home` /
    `custom-icon.icns` children (they live inside it).
  - **Application Support:** list only the **independent** owned roots that are not
    nested in one another — `Profiles/<UUID>`, `CodexHomes/<UUID>`,
    `CustomIcons/<UUID>.icns` (each a separate top-level root).
  - The planner asserts no path in the set is a prefix of another; an overlap is a
    programming error and aborts before any move (fail closed).
- **Partial-result state/reporting:** artifacts are moved independently; the op
  returns a per-artifact result set `{ path, moved | failed(reason) }`. If some
  succeed and some fail, the UI reports exactly which moved and which remain,
  offers retry for the failures, and leaves the record/orphan state consistent
  with what actually moved. A `trashItem` failure (read-only volume, absent) is a
  **surfaced no-op** — never a fallback to permanent delete.
- **Idempotency:** already-absent artifact → no-op; a second run trashes only
  what remains.
- **Never** part of any "Clean All"; there is no bulk destructive action.

### 6.6 Archived-state enforcement across runtime consumers (Codex-A #1)

Archived rows keep their assignments in the record (I3) but are **ineligible at
runtime** everywhere. Each consumer must exclude `state == .archived` (defense in
depth — even where `pinToMenuBar` is already cleared):

- **Active-instance set / hotkey routing** — `activeAppProfileInstanceIDs`
  ([`KlikProInput.swift:47`](../Sources/KlikProInput.swift), `:81`, `:94`) and the
  resolved mapping at [`:117`](../Sources/KlikProInput.swift): exclude archived.
- **Special-Feature hotkey registration** —
  [`KlikProInput.swift:1507`](../Sources/KlikProInput.swift) `config.instances.filter{…}`:
  exclude archived.
- **Menu-bar population** — the pin loop
  [`KlikProInput.swift:652`](../Sources/KlikProInput.swift)
  (`where instance.pinToMenuBar`): also require `state != .archived`.
- **Mouse-button routing** — instance lookup by `mouseButton`
  ([`KlikProApp.swift:1835`](../Sources/KlikProApp.swift), `:3359`; the
  legacy/target lookups in `KlikProInput`): exclude archived.
- **Open / launcher lookup** — `generatedLauncherURL`
  ([`KlikProApp.swift:4593`](../Sources/KlikProApp.swift)): archived is ineligible.
- **Conflict validation / launchability** — `launchableAppProfileInstanceIDs`
  ([`:2850`](../Sources/KlikProApp.swift)), `recomputeConflictBadges`
  ([`:2899`](../Sources/KlikProApp.swift)), `availableInstances`
  ([`:1821`](../Sources/KlikProApp.swift)): archived excluded from the **active**
  conflict set (so an archived hotkey never blocks an active one — and Restore's
  revalidation, §6.2, re-adds it to the check).
- **Healing** — `healManagedInstances`
  ([`AppProfileManager.swift:653`](../Sources/Duplication/AppProfileManager.swift)):
  skip archived rows (their launcher is intentionally absent; healing must not try
  to update/regenerate it).
- **UI lists** — App Profiles + Mappings visibility filters
  ([`AppProfilesUI.swift:672`](../Sources/AppProfilesUI.swift), `:863`): exclude
  archived; archived appears **only** in Data & Maintenance.

---

## 7. UI — Advanced ▸ Data & Maintenance

A new **lock-gated** section in `AdvancedSettingsContentView`
([`AppProfilesUI.swift:940`](../Sources/AppProfilesUI.swift)), below the existing
vault controls (already behind the padlock, unlocked via
`confirmUnlockAdvancedSettings` [`KlikProApp.swift:2619`](../Sources/KlikProApp.swift)).

- **Scan** → reconcile records + roots scan → a list grouped by state (Healthy
  collapses to a count; problem states expand). Each item: label (or "unknown" for
  orphans), UUID, source app, data path, size, marker present/absent.
- Per-item actions by state: **Repair**, **Archive** / **Restore**, **Forget
  Entry**, **Move Data to Trash**. **No "Clean All."** Destructive actions (Forget,
  Trash) show an impact summary with exact paths + explicit confirm. **Needs Manual
  Review** items are a separate group with **no** Klik PRO action (path only).
- **Profile cards** (use the dead `health:` seam,
  [`AppProfilesUI.swift:357`](../Sources/AppProfilesUI.swift)): inline badge for
  non-Healthy active states, e.g. "Missing Launcher — Repair"; **Open routes to
  Repair** for a Missing-Launcher row instead of a silent failure. Archived rows
  are hidden here (§6.6).
- Gear-menu everyday action changes from destructive "Remove…" to **"Archive…"**
  (reversible; alert explains record + data are preserved and it can be restored).
  True deletion lives only in Data & Maintenance.
- **Auto-refresh (Codex-A #5):** the `didBecomeActiveNotification` hook
  ([`KlikProApp.swift:2901`](../Sources/KlikProApp.swift)) and the "Refresh App
  List" handler must **recompute the full reconciliation inventory** (the new
  states, not just the runtime-health dict) and push it to **both** views — the
  App Profiles cards (`setInstances` + health/inventory) **and** the Data &
  Maintenance list. Returning from Finder after a manual launcher deletion then
  reclassifies to Missing Launcher (repairable) immediately.

---

## 8. Failure handling (summary)

- Reused primitives: exclusive `ManagedInstanceLock`; two-pass fail-closed process
  scan; marker gate; stage→commit→rollback; symlink rejection; standardized paths.
- Injectable trash op → surfaced no-op on failure; never permanent delete; partial
  results reported per artifact (§6.5).
- `regenerateLauncher` failure (source missing/unverified) → clear reason, data
  untouched.
- Manifest write failure → surfaced lag; config authoritative; next reconciliation
  repairs it (I4).
- Vault offline → archived vault records show "data folder not connected"; Restore
  / Move-to-Trash blocked with a clear message; recovery still possible once
  reconnected (manifest v2 + vault-owned assets).
- Reference-cleanup failure → archive still succeeds; leftover surfaced (I7).
- Restore conflict → stays archived; explains what to change (§6.2).

---

## 9. MVP & incremental sequence

**Phase A — Reconcile, Repair, Archive/Restore (no user-data deletion).**
1. Schema 11→12 (`state`, `archivedAt`) + manifest 1→2 (`archived`, `menuColor`,
   `customIcon`) + vault-owned custom-icon asset + migration/fallback.
2. `updateVaultManifest` #6 fix (include archived, data-bearing records).
3. Reconciliation engine + evidence-aware classification (6 states); full-inventory
   auto-refresh into both views (Codex-A #5).
4. **Archived enforcement across all runtime consumers** (§6.6) + card badges +
   Open→Repair routing.
5. Icon-preserving archive launcher removal (Codex-A #4).
6. Advanced ▸ Data & Maintenance: **Scan**, **Repair**, **Archive**, **Restore**
   (with conflict revalidation via the extracted shared pure evaluator, §6.2).
   Gear "Remove…" → "Archive…". Reconciliation also sweeps legacy stale staging
   paths (§6.1).
   *Delivers the reported fix and the #6 recovery fix with zero data-deletion code.*

**Phase B — Destructive cleanup (separate review).**
7. **Forget Entry** (record + manifest removal; no user-data deletion).
8. **Move Data to Trash** (injectable trash op, marker-gated, exclusive lock +
   process scan, partial-result reporting); inspect/export for orphans;
   manual-review surfacing for markerless folders.

Phase A ships alone; Phase B builds on it behind the same lock gate.

---

## 10. Acceptance criteria

**A. ChatGPT T manual-deletion (the reported case).**
Given a Healthy managed "ChatGPT T" with a pinned Dock tile, when the user deletes
`~/Applications/Klik PRO/ChatGPT T.app` in Finder and returns to Klik PRO (activation)
or presses Scan:
- classified **Missing Launcher** instead of a normal-looking-but-broken row; card
  shows "Missing Launcher — Repair"; **Open routes to Repair**, not silent failure;
  data intact.
- **Repair Launcher** rebuilds the launcher for the **same UUID** (no duplicate
  row, no data modification); returns to **Healthy** and launches.
- If ChatGPT.app is missing/unverified, Repair is blocked with a clear reason; no
  change.

**B. Archive / Restore round-trip.**
- Archive keeps the row (`state=archived`), data, recipe, custom icon (asset
  preserved — Codex-A #4), `menuColor`, `hotkey`, `mouseButton`, and the vault
  manifest record; removes the launcher and **only** the exact Dock entry (a
  sibling entry with a similar name is untouched); menu-bar pin cleared.
- **Archived row is runtime-ineligible everywhere** (§6.6): no hotkey/mouse routing,
  not in the active conflict set, no menu-bar button, not healed, not Open-able,
  hidden from App Profiles/Mappings lists.
- Restore **revalidates conflicts first**; on conflict stays archived and names the
  conflict; on clean, rebuilds the launcher (same UUID), returns to Healthy,
  reactivates hotkey/mouse, and **does not** re-add the Dock entry or re-enable the
  menu-bar pin (I8).
- If Dock cleanup can't be verified, Archive still succeeds; the leftover Dock
  entry is surfaced with a manual-remediation note.

**C. #6 vault recovery regression.**
- Archiving a **vault** profile leaves its v2 record (incl. `menuColor`,
  `customIcon`) in `vault.json`; a simulated reinstall → `adoptVault` restores it
  **with the exact custom icon** from the vault-owned asset. (Fails on current code.)

**D. Evidence-aware orphans.**
- Marker-owned, recipe-less folder → **Orphaned Data**: inspect/export shown; only
  Move-to-Trash; never reconstructed. Markerless → **Needs Manual Review**: path
  only, no Klik PRO delete.

**E. Destructive safety.**
- Move-to-Trash uses the (injected) trash op — recoverable, never permanent;
  refused (nothing moved) under lock contention, incomplete scan, referencing
  process, missing marker, or a symlink escaping the roots; **partial results are
  reported per artifact.**

**F. Migration.**
- A v1.2.0 (schema 11) config loads under 12 with all rows `.active`, no data
  moved, no row re-keyed; a schema-1 `vault.json` reads with new fields defaulted;
  an existing vault profile with an Application-Support custom icon gains a
  vault-owned `custom-icon.icns` on first heal/adopt (or falls back to source icon).

---

## 11. Test matrix (write-first)

- Classification: each of the 6 states from fixtures (active/archived, recipe vs
  marker-only vs markerless).
- **Archived enforcement**: unit-test each consumer in §6.6 excludes an archived
  row (active-set, hotkey registration, menu-bar loop, mouse routing, launchable/
  conflict set, healing skip, UI visibility).
- Archive (ordered per §6.1): **persist-fail → disk untouched, record stays
  active** (no artifact staged before the commit point); on success, row kept
  `state=archived`; data + recipe + **custom-icon asset** +
  `menuColor`/`hotkey`/`mouseButton` + **manifest record** retained; launcher
  removed; only the exact Dock entry removed (a similarly-named sibling untouched).
- **Crash-after-persist recovery**: fixture with `state=archived` + a still-present
  launcher (and stale manifest / un-cleaned Dock ref) → startup reconciliation
  completes icon-preserving removal, repairs the manifest, re-surfaces the ref;
  idempotent on repeat.
- **Legacy staging sweep**: an orphaned `.<UUID>-…-removing-…` bundle under the
  Launchers root → reconciliation removes it (UUID/marker/name-verified,
  symlink-rejecting); a non-matching hidden dir is left untouched.
- **Icon-preserving removal** (Codex-A #4): archive removal keeps
  `CustomIcons/<UUID>.icns` / vault-owned asset; the permanent removal drops it.
- **Shared conflict evaluator** (Codex-A r2 #3): `appProfileAssignmentConflicts`
  is pure (no AppKit), unit-tested directly (duplicate hotkey, duplicate mouse
  button, reserved Command-Tab, archived excluded), and is the **same** entry point
  the UI badges and Restore call.
- Restore: conflict (via the shared evaluator) → stays archived + names conflict;
  clean → launcher regenerated (same UUID, golden), data untouched, hotkey/mouse
  reactivated, **no** Dock/menu re-pin; source-missing → refused.
- Repair Launcher: Missing Launcher → Healthy, data untouched; source missing →
  refused.
- **#6 regression**: archived vault profile present in v2 `vault.json`; adopt
  restores it with the exact custom icon.
- Forget Entry: only Missing Data / stale; removes manifest record; user data
  untouched; absent → no-op.
- **Move-to-Trash (injected op)**: item goes to the **injected** destination
  (never real Trash); marker-gated; lock-contention / process-referencing /
  incomplete-scan → fail closed, nothing moved; **partial-result reporting** when
  some artifacts move and some fail; `trashItem` failure → surfaced no-op.
- **Non-overlapping artifact plan** (Codex-A r2 #2): vault instance → the plan is
  exactly one path (`<Vault>/Instances/<UUID>`), never the container + its
  children; Application Support → only independent roots
  (`Profiles/<UUID>`, `CodexHomes/<UUID>`, `CustomIcons/<UUID>.icns`); a fixture
  with a child nested under a listed ancestor is deduped/aborted before any move.
- Orphan qualification: in-config/active/manifest → never an orphan; markerless →
  manual-review; symlink escaping roots rejected; vault root / non-UUID never
  enumerated.
- Idempotency of every transition.
- Migration 11→12, manifest 1→2, and vault-owned-icon migration/fallback.
- Auto-refresh recomputes full inventory and updates **both** views on a simulated
  launcher deletion.

---

## 12. Governance

- **Spec only.** No code, commit, push, tag, or release from this step. The spec
  should be committed onto `codex/v1.2.1-data-maintenance` when implementation is
  authorized.
- **Base:** `origin/main` `954540d` (released v1.2.0), worktree
  `worktrees/codex-a-v1.2.1-data-maintenance`, branch
  `codex/v1.2.1-data-maintenance`; baseline `./tools/check.sh` green at
  `build/check-20260722-014354`. Preserve v1.2.0 behaviour (Archive is a refinement
  of the existing `remove(deleteProfileData:false)` path — keep row + manifest
  record + custom-icon asset, plus surgical reference cleanup — not a rewrite).
- Sequence: Aminudin review → **Codex-A independent review** → Aminudin authorizes
  implementation → build Phase A → review → on-machine test → Phase B likewise.
  **Aminudin merges**; nothing pushed/tagged/released without explicit approval.

---

## 13. Non-goals

- No general filesystem cleanup or "free up space" scanning.
- No bulk / "Clean All" destructive action.
- No deletion of `.legacyExternal` instances or user-made folders.
- No touching `/Applications`, source apps, the vault root itself, `~`, or any path
  outside the Klik PRO roots.
- No reconstructing a profile from a recipe-less (marker-only) data folder.
- ~~No permanent deletion anywhere — Trash only.~~ ⚠️ **Reversed by the
  2026-07-22 owner override:** Delete Permanently is an explicit, per-action
  user choice (see the revision note at the top). Trash remains the default.
