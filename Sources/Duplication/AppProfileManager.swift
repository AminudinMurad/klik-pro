import Foundation

enum AppProfileManagerError: Error, Equatable {
    case sourceChanged
    case creationDisabled(String)
    case duplicateInstanceID
    case duplicateLabel
    case materializationFailed
    case persistenceFailed
    case externalInstance
    case launcherUnavailable
    case launcherCleanupFailed
    case invalidAssignments
    case processScanIncomplete
    case profileInUse
    case profileCleanupFailed
    case conversionUnavailable
    /// A user-chosen icon image could not be decoded or is too small.
    case iconImageInvalid
    /// Adopt was requested without a configured/mounted vault root.
    case vaultUnavailable
    /// The candidate folder carries no valid `vault.json`, so it is refused:
    /// arbitrary or foreign folders are never adopted.
    case vaultManifestInvalid
    case invalidLifecycleState
    case repairUnavailable
    /// Forget Entry was requested for a record whose data is still present, or
    /// for a non-managed row. Forget is gated to Missing Data / stale records.
    case forgetUnavailable
    /// A data-removal target failed its ownership/path gate, so nothing was
    /// touched (e.g. a markerless orphan, or a swapped path).
    case dataRemovalUnavailable
}

struct AppProfileCandidate: Identifiable, Equatable {
    let app: InstalledApp
    let engine: AppProfileEngine
    let eligibility: AppProfileEligibility

    var id: UUID { app.id }
    var canCreate: Bool {
        eligibility.kind != .unsupported && eligibility.compatibilityRuleID != nil
    }
}

struct AppProfileRemovalResult: Equatable {
    let config: KlikProConfig
    let launcherCleanupCompleted: Bool
    let profileCleanupCompleted: Bool
    let profileDeleted: Bool
}

struct VaultAdoptionResult: Equatable {
    let config: KlikProConfig
    let adopted: [AppProfileInstance]
    /// Manifest records that could not be adopted this pass (missing data
    /// directory, missing source app, rule mismatch, label collision). Their
    /// vault data is never touched; a later adopt can pick them up.
    let skippedInstanceIDs: [UUID]
}

enum AppProfileMaintenanceHealth: Equatable {
    case healthy
    case recoverableArchived
    case missingLauncher
    case missingData
    /// Marker-owned data on disk with no trustworthy config record — reclaimable
    /// via Move Data to Trash / Delete. Surfaced from `scanOrphans`, never
    /// returned by `maintenanceHealth(for:)` (which is per config record).
    case orphanedData
    /// A UUID-named data folder under a Klik PRO root that carries no ownership
    /// marker — surfaced for the user's information only; Klik PRO offers no
    /// delete action for it.
    case needsManualReview
}

/// One record-less data root found on disk (`scanOrphans`). `.orphanedData`
/// carries a marker (Klik PRO owns it); `.needsManualReview` does not.
struct OrphanFinding: Equatable {
    let instanceID: UUID
    let storage: AppProfileStorage
    let state: AppProfileMaintenanceHealth
    let dataPaths: [URL]
    let sizeBytes: Int64
    let markerPresent: Bool
}

/// A validated set of owned artifacts to reclaim, with the config row (if any)
/// the removal should also drop once its data is gone.
struct DataRemovalTarget: Equatable {
    let instanceID: UUID
    let storage: AppProfileStorage
    let artifacts: [DataRemovalArtifact]
    /// Best-effort total size of the artifacts, for the confirmation summary.
    let sizeBytes: Int64
    /// True when the target came from a config record (direct delete on a
    /// visible row); false for a record-less orphan.
    let hasConfigRecord: Bool

    var paths: [URL] { artifacts.map { $0.url } }
}

struct DataRemovalArtifact: Equatable {
    let url: URL
    let kind: OwnedArtifactKind
}

enum DataRemovalArtifactOutcome: Equatable {
    case removed(trashURL: URL?)
    case failed
}

struct DataRemovalArtifactResult: Equatable {
    let url: URL
    let outcome: DataRemovalArtifactOutcome
}

struct DataRemovalResult: Equatable {
    let config: KlikProConfig
    let perArtifact: [DataRemovalArtifactResult]
    let mode: DataRemovalMode

    var allRemoved: Bool {
        !perArtifact.isEmpty && perArtifact.allSatisfy {
            if case .removed = $0.outcome { return true }
            return false
        }
    }
}

struct AppProfileArchiveResult: Equatable {
    let config: KlikProConfig
    let launcherCleanupCompleted: Bool
}

/// Registry-gated App Profile lifecycle service. It re-inspects a scanned bundle
/// before every managed transition and keeps materialization/config changes
/// transactional so failures remain rollback-safe.
struct AppProfileManager {
    private let scanApplications: ([URL]?) -> [InstalledApp]
    private let inspectApplication: (URL) -> InstalledApp?
    private let detector: EngineDetector
    private let registry: AppCompatibilityRegistry
    private let generator: LauncherGenerator
    private let processInspector: ManagedProcessInspector
    private let persist: (KlikProConfig) -> Bool
    private let waitBetweenProfileScans: () -> Void
    private let resolveLegacyTarget: (AppProfileInstance) -> QuickLaunchTarget?

    init(
        scanner: AppScanner = AppScanner(),
        detector: EngineDetector = EngineDetector(),
        registry: AppCompatibilityRegistry = .production,
        generator: LauncherGenerator = LauncherGenerator(),
        processInspector: ManagedProcessInspector = ManagedProcessInspector(),
        persist: @escaping (KlikProConfig) -> Bool = KlikProConfigStore.save,
        waitBetweenProfileScans: @escaping () -> Void = {
            Thread.sleep(forTimeInterval: 0.15)
        },
        resolveLegacyTarget: ((AppProfileInstance) -> QuickLaunchTarget?)? = nil,
        scanApplications: (([URL]?) -> [InstalledApp])? = nil,
        inspectApplication: ((URL) -> InstalledApp?)? = nil
    ) {
        self.scanApplications = scanApplications ?? { scanner.scan(searchRoots: $0) }
        self.inspectApplication = inspectApplication ?? { scanner.inspect($0) }
        self.detector = detector
        self.registry = registry
        self.generator = generator
        self.processInspector = processInspector
        self.persist = persist
        self.waitBetweenProfileScans = waitBetweenProfileScans
        self.resolveLegacyTarget = resolveLegacyTarget ?? { $0.legacyQuickLaunchTarget }
    }

    func candidate(for app: InstalledApp) -> AppProfileCandidate {
        AppProfileCandidate(
            app: app,
            engine: detector.detect(app),
            eligibility: detector.eligibility(for: app, registry: registry)
        )
    }

    func candidates(searchRoots: [URL]? = nil) -> [AppProfileCandidate] {
        scanApplications(searchRoots).map(candidate(for:))
    }

    /// User-facing catalogue: scanning remains automatic and internal, while
    /// only apps with an explicit approved compatibility rule are returned.
    func supportedCandidates(searchRoots: [URL]? = nil) -> [AppProfileCandidate] {
        candidates(searchRoots: searchRoots).filter { $0.canCreate }
    }

    func create(
        from selected: AppProfileCandidate,
        label requestedLabel: String? = nil,
        environmentOverrides: [String: String] = [:],
        config: KlikProConfig,
        instanceID: UUID = UUID(),
        pinToMenuBar: Bool = false
    ) throws -> (config: KlikProConfig, instance: AppProfileInstance) {
        guard let current = inspectApplication(selected.app.bundleURL),
              sameSource(current, selected.app) else {
            throw AppProfileManagerError.sourceChanged
        }
        let currentCandidate = candidate(for: current)
        guard currentCandidate.canCreate,
              let ruleID = currentCandidate.eligibility.compatibilityRuleID else {
            throw AppProfileManagerError.creationDisabled(currentCandidate.eligibility.reason)
        }
        guard !config.instances.contains(where: { $0.id == instanceID }) else {
            throw AppProfileManagerError.duplicateInstanceID
        }

        let cleanedLabel = requestedLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (cleanedLabel?.isEmpty == false ? cleanedLabel : nil) ?? current.displayName
        guard !config.instances.contains(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) else {
            throw AppProfileManagerError.duplicateLabel
        }
        let storage = try newInstanceStorage(for: config)
        let launcherURL = generator.launcherURL(for: instanceID, label: String(label.prefix(80)))
        guard let profileURL = try? generator.profileURL(for: instanceID, storage: storage) else {
            throw AppProfileManagerError.creationDisabled(
                "The configured data folder is unavailable."
            )
        }
        let resolvedEnvironment = try ruleResolvedEnvironment(
            ruleID: ruleID,
            instanceID: instanceID,
            storage: storage,
            overriding: environmentOverrides
        )
        var instance = AppProfileInstance(
            id: instanceID,
            label: String(label.prefix(80)),
            launcherKind: .managed,
            launcherPath: launcherURL.path,
            profileDirectory: profileURL.path,
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: current.bundleIdentifier,
                bundleURL: current.bundleURL.path
            ),
            storage: storage,
            environmentOverrides: resolvedEnvironment,
            pinToMenuBar: pinToMenuBar,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0,
                    keyDisplay: "A",
                    command: false,
                    option: false,
                    control: true,
                    shift: false
                )
            ),
            mouseButton: nil,
            lastDetectedEngine: currentCandidate.engine,
            lastVerifiedAppVersion: current.version,
            lastVerifiedTeamIdentifier: current.teamIdentifier,
            compatibilityRuleID: ruleID
        )

        let materialization: ManagedLauncherMaterialization
        do {
            materialization = try generator.materialize(instance: instance, sourceApp: current)
        } catch {
            throw AppProfileManagerError.materializationFailed
        }
        instance.iconPath = materialization.iconURL?.path
        createHomeSymlinkIfRuleRequests(for: instance)

        var updated = config
        updated.instances.append(instance)
        guard appProfileAssignmentsAreValid(updated) else {
            generator.rollbackNewMaterialization(for: instance)
            throw AppProfileManagerError.invalidAssignments
        }
        guard persist(updated) else {
            generator.rollbackNewMaterialization(for: instance)
            throw AppProfileManagerError.persistenceFailed
        }
        if instance.storage == .vault {
            updateVaultManifest(config: updated)
        }
        return (updated, instance)
    }

    /// Explicitly converts one known v1 legacy row. The external bundle and any data
    /// it owns are never moved, renamed, or deleted. A new UUID-keyed managed profile
    /// is materialized first, then assignments transfer in the same config write that
    /// suppresses the legacy row.
    func convertLegacy(
        instanceID: UUID,
        config: KlikProConfig,
        managedInstanceID: UUID = UUID()
    ) throws -> (config: KlikProConfig, instance: AppProfileInstance) {
        guard let legacy = config.instances.first(where: { $0.id == instanceID }),
              legacy.launcherKind == .legacyExternal,
              let target = resolveLegacyTarget(legacy),
              !config.instances.contains(where: { $0.id == managedInstanceID }) else {
            throw AppProfileManagerError.conversionUnavailable
        }
        let sourceURL = URL(fileURLWithPath: legacy.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        guard let current = inspectApplication(sourceURL),
              current.bundleURL == sourceURL,
              current.bundleIdentifier == legacy.source.bundleIdentifier else {
            throw AppProfileManagerError.sourceChanged
        }
        let currentCandidate = candidate(for: current)
        guard currentCandidate.canCreate,
              let ruleID = currentCandidate.eligibility.compatibilityRuleID else {
            throw AppProfileManagerError.creationDisabled(currentCandidate.eligibility.reason)
        }

        // Q6 decision (2026-07-16): conversion derives the environment fresh from
        // the explicit rule; the legacy row's own env is deliberately not merged.
        let storage = try newInstanceStorage(for: config)
        let resolvedEnvironment = try ruleResolvedEnvironment(
            ruleID: ruleID,
            instanceID: managedInstanceID,
            storage: storage,
            overriding: [:]
        )
        var managed = try managedInstance(
            app: current,
            candidate: currentCandidate,
            ruleID: ruleID,
            instanceID: managedInstanceID,
            label: legacy.label,
            storage: storage,
            environmentOverrides: resolvedEnvironment
        )
        managed.menuColor = legacy.menuColor
        managed.pinToMenuBar = legacy.pinToMenuBar
        managed.hotkey = legacy.hotkey
        managed.mouseButton = legacy.mouseButton

        let materialization: ManagedLauncherMaterialization
        do {
            materialization = try generator.materialize(instance: managed, sourceApp: current)
        } catch {
            throw AppProfileManagerError.materializationFailed
        }
        managed.iconPath = materialization.iconURL?.path
        createHomeSymlinkIfRuleRequests(for: managed)

        var updated = config
        updated.instances.removeAll { $0.id == legacy.id }
        updated.suppressedLegacyInstanceIDs.insert(target.legacyInstanceID)
        updated.instances.append(managed)
        guard appProfileAssignmentsAreValid(updated) else {
            generator.rollbackNewMaterialization(for: managed)
            throw AppProfileManagerError.invalidAssignments
        }
        guard persist(updated) else {
            generator.rollbackNewMaterialization(for: managed)
            throw AppProfileManagerError.persistenceFailed
        }
        if managed.storage == .vault {
            updateVaultManifest(config: updated)
        }
        return (updated, managed)
    }

    func updateManagedInstance(
        instanceID: UUID,
        label requestedLabel: String,
        menuColor: AppProfileMenuColor?,
        pinToMenuBar: Bool,
        hotkey: ShortcutMapping,
        mouseButton: QuickLaunchMouseButton?,
        config: KlikProConfig
    ) throws -> KlikProConfig {
        guard let index = config.instances.firstIndex(where: { $0.id == instanceID }),
              config.instances[index].launcherKind == .managed else {
            throw AppProfileManagerError.externalInstance
        }
        let label = requestedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw AppProfileManagerError.invalidAssignments }
        guard !config.instances.contains(where: {
            $0.id != instanceID && $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) else {
            throw AppProfileManagerError.duplicateLabel
        }
        var updatedConfig = config
        let previous = updatedConfig.instances[index]
        updatedConfig.instances[index].label = String(label.prefix(80))
        updatedConfig.instances[index].menuColor = menuColor
        updatedConfig.instances[index].pinToMenuBar = pinToMenuBar
        updatedConfig.instances[index].hotkey = hotkey
        updatedConfig.instances[index].mouseButton = mouseButton
        let movedLauncherURL: URL
        do {
            movedLauncherURL = try generator.updateDisplayName(
                from: previous,
                to: updatedConfig.instances[index]
            )
            updatedConfig.instances[index].launcherPath = movedLauncherURL.path
            updatedConfig.instances[index].iconPath = movedLauncherURL
                .appendingPathComponent("Contents/Resources/AppIcon.icns")
                .path
        } catch {
            throw AppProfileManagerError.materializationFailed
        }
        guard appProfileAssignmentsAreValid(updatedConfig) else {
            _ = try? generator.updateDisplayName(from: updatedConfig.instances[index], to: previous)
            throw AppProfileManagerError.invalidAssignments
        }
        guard persist(updatedConfig) else {
            _ = try? generator.updateDisplayName(from: updatedConfig.instances[index], to: previous)
            throw AppProfileManagerError.persistenceFailed
        }
        // The visible home symlink is cosmetic: re-derive it from the new
        // label after the rename has fully persisted; failures are non-fatal.
        if previous.label != updatedConfig.instances[index].label {
            generator.removeHomeSymlinks(for: instanceID, storage: previous.storage)
            createHomeSymlinkIfRuleRequests(for: updatedConfig.instances[index])
        }
        if updatedConfig.instances[index].storage == .vault {
            updateVaultManifest(config: updatedConfig)
        }
        return updatedConfig
    }

    // MARK: Custom icons

    /// How a managed profile's icon should be produced. `.image` replaces it
    /// with a user file; `.tint`/`.badge` derive from the source app's own icon;
    /// `.reset` restores the source icon and drops any persisted custom copy.
    enum IconEdit {
        case image(URL)
        case tint(AppProfileMenuColor)
        case badge(AppProfileMenuColor)
        case reset
    }

    /// Applies an icon edit to one managed instance and persists the result.
    /// External/legacy rows are rejected. Only the launcher bundle and the
    /// per-instance persisted icon change — profile data is never touched.
    func updateManagedIcon(
        instanceID: UUID,
        edit: IconEdit,
        config: KlikProConfig
    ) throws -> KlikProConfig {
        guard let index = config.instances.firstIndex(where: { $0.id == instanceID }),
              config.instances[index].launcherKind == .managed else {
            throw AppProfileManagerError.externalInstance
        }
        let instance = config.instances[index]
        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        let resolvedIconPath: String?
        do {
            switch edit {
            case .image(let imageURL):
                resolvedIconPath = try generator
                    .setCustomIcon(fromImageAt: imageURL, for: instance).path
            case .tint(let color):
                resolvedIconPath = try generator.setTintedIcon(
                    color: color.iconColor, for: instance, sourceBundleURL: sourceURL
                ).path
            case .badge(let color):
                resolvedIconPath = try generator.setBadgedIcon(
                    color: color.iconColor,
                    letter: instance.label,
                    for: instance,
                    sourceBundleURL: sourceURL
                ).path
            case .reset:
                resolvedIconPath = try generator.resetCustomIcon(
                    for: instance, sourceBundleURL: sourceURL
                )?.path
            }
        } catch LauncherGeneratorError.iconImageInvalid {
            throw AppProfileManagerError.iconImageInvalid
        } catch {
            throw AppProfileManagerError.materializationFailed
        }

        var updated = config
        updated.instances[index].iconPath = resolvedIconPath
        guard persist(updated) else {
            throw AppProfileManagerError.persistenceFailed
        }
        if updated.instances[index].storage == .vault {
            switch edit {
            case .reset:
                generator.removeVaultCustomIcon(for: updated.instances[index])
            default:
                _ = generator.synchronizeCustomIconToVault(for: updated.instances[index])
            }
            updateVaultManifest(config: updated)
        }
        return updated
    }

    func launcherURL(for instance: AppProfileInstance) throws -> URL {
        if instance.launcherKind == .managed {
            let storedSourceURL = URL(
                fileURLWithPath: instance.source.bundleURL,
                isDirectory: true
            ).standardizedFileURL
            guard let current = inspectApplication(storedSourceURL),
                  current.bundleURL.standardizedFileURL == storedSourceURL,
                  current.bundleIdentifier == instance.source.bundleIdentifier else {
                throw AppProfileManagerError.launcherUnavailable
            }
            let currentCandidate = candidate(for: current)
            guard currentCandidate.canCreate else {
                throw AppProfileManagerError.creationDisabled(
                    currentCandidate.eligibility.reason
                )
            }
            do {
                _ = try generator.validatedProfileURL(for: instance)
                return try generator.validatedLauncherURL(for: instance)
            } catch {
                throw AppProfileManagerError.launcherUnavailable
            }
        }

        let launcherURL = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
            .standardizedFileURL
        guard launcherURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: launcherURL.path) else {
            throw AppProfileManagerError.launcherUnavailable
        }
        return launcherURL
    }

    /// Returns only a structurally validated Klik PRO-generated launcher. This is
    /// the common user-facing entry point shared by the App Profiles Open button,
    /// Spotlight, and the Dock; the launcher performs its own source/rule checks.
    func generatedLauncherURL(for instance: AppProfileInstance) throws -> URL {
        guard instance.launcherKind == .managed, instance.state == .active else {
            throw AppProfileManagerError.externalInstance
        }
        do {
            return try generator.validatedLauncherURL(for: instance)
        } catch {
            throw AppProfileManagerError.launcherUnavailable
        }
    }

    func maintenanceHealth(for instance: AppProfileInstance) -> AppProfileMaintenanceHealth {
        guard instance.launcherKind == .managed,
              instance.profileOwnership == .managed else {
            return .healthy
        }
        guard (try? generator.validatedProfileURL(for: instance)) != nil else {
            return .missingData
        }
        if instance.state == .archived {
            return .recoverableArchived
        }
        // A launcher can still exist while its embedded runtime is stale (for
        // example after the vendor renames Electron's framework). Surface this
        // as repairable so Advanced offers Repair instead of reporting Healthy.
        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        guard let current = inspectApplication(sourceURL),
              current.bundleIdentifier == instance.source.bundleIdentifier,
              candidate(for: current).canCreate,
              candidate(for: current).eligibility.compatibilityRuleID == instance.compatibilityRuleID
        else { return .missingLauncher }
        return (try? generator.validatedLauncherURL(for: instance)) == nil
            ? .missingLauncher
            : .healthy
    }

    /// Rebuilds only a missing generated launcher. The owned profile directory
    /// is validated but never created, moved, or modified.
    func repairLauncher(
        instanceID: UUID,
        config: KlikProConfig
    ) throws -> KlikProConfig {
        guard let index = config.instances.firstIndex(where: { $0.id == instanceID }),
              config.instances[index].state == .active,
              maintenanceHealth(for: config.instances[index]) == .missingLauncher else {
            throw AppProfileManagerError.repairUnavailable
        }
        let source = try verifiedSource(for: config.instances[index])
        let materialization: ManagedLauncherMaterialization
        do {
            materialization = try generator.regenerateLauncher(
                instance: config.instances[index],
                sourceApp: source
            )
        } catch {
            throw AppProfileManagerError.materializationFailed
        }
        var updated = config
        updated.instances[index].iconPath = materialization.iconURL?.path
        guard persist(updated) else {
            if let staged = try? generator.stageLauncherRemoval(for: updated.instances[index]) {
                try? generator.commitLauncherRemoval(staged, preserveCustomIcon: true)
            }
            throw AppProfileManagerError.persistenceFailed
        }
        if updated.instances[index].storage == .vault {
            updateVaultManifest(config: updated)
        }
        return updated
    }

    /// Archives a managed profile without touching its data or assignments.
    /// Config persistence is the commit point; launcher/reference cleanup is
    /// idempotent and may be completed by a later reconciliation pass.
    func archive(
        instanceID: UUID,
        at date: Date = Date(),
        config: KlikProConfig
    ) throws -> AppProfileArchiveResult {
        guard let index = config.instances.firstIndex(where: { $0.id == instanceID }),
              config.instances[index].launcherKind == .managed,
              config.instances[index].profileOwnership == .managed else {
            throw AppProfileManagerError.externalInstance
        }
        guard config.instances[index].state == .active else {
            return AppProfileArchiveResult(config: config, launcherCleanupCompleted: true)
        }
        var updated = config
        updated.instances[index].state = .archived
        updated.instances[index].archivedAt = date
        updated.instances[index].pinToMenuBar = false
        guard persist(updated) else {
            throw AppProfileManagerError.persistenceFailed
        }
        if updated.instances[index].storage == .vault {
            updateVaultManifest(config: updated)
        }
        var cleanupCompleted = true
        do {
            if let staged = try generator.stageLauncherRemoval(for: updated.instances[index]) {
                try generator.commitLauncherRemoval(staged, preserveCustomIcon: true)
            }
        } catch {
            cleanupCompleted = false
        }
        generator.removeHomeSymlinks(
            for: updated.instances[index].id,
            storage: updated.instances[index].storage
        )
        return AppProfileArchiveResult(
            config: updated,
            launcherCleanupCompleted: cleanupCompleted
        )
    }

    func restore(
        instanceID: UUID,
        config: KlikProConfig
    ) throws -> KlikProConfig {
        guard let index = config.instances.firstIndex(where: { $0.id == instanceID }),
              config.instances[index].state == .archived else {
            throw AppProfileManagerError.invalidLifecycleState
        }
        var updated = config
        updated.instances[index].state = .active
        updated.instances[index].archivedAt = nil
        guard appProfileAssignmentsAreValid(updated) else {
            throw AppProfileManagerError.invalidAssignments
        }
        let source = try verifiedSource(for: config.instances[index])
        var generated = false
        if (try? generator.validatedLauncherURL(for: config.instances[index])) == nil {
            do {
                let materialization = try generator.regenerateLauncher(
                    instance: config.instances[index],
                    sourceApp: source
                )
                updated.instances[index].iconPath = materialization.iconURL?.path
                generated = true
            } catch {
                throw AppProfileManagerError.materializationFailed
            }
        }
        guard persist(updated) else {
            if generated,
               let staged = try? generator.stageLauncherRemoval(for: updated.instances[index]) {
                try? generator.commitLauncherRemoval(staged, preserveCustomIcon: true)
            }
            throw AppProfileManagerError.persistenceFailed
        }
        createHomeSymlinkIfRuleRequests(for: updated.instances[index])
        if updated.instances[index].storage == .vault {
            updateVaultManifest(config: updated)
        }
        return updated
    }

    /// Forget Entry (spec §6.4): drops a stale config row (and its vault
    /// manifest record) whose profile data is already gone. Touches **no** user
    /// data — a launcher is not user data, so any residual launcher bundle is
    /// still cleaned up. Data-read-only, so no lock/scan (I9). Config persist is
    /// the commit point; a persist failure leaves the disk untouched.
    func forget(
        instanceID: UUID,
        config: KlikProConfig,
        allowStale: Bool = false
    ) throws -> AppProfileRemovalResult {
        guard let instance = config.instances.first(where: { $0.id == instanceID }) else {
            return AppProfileRemovalResult(
                config: config,
                launcherCleanupCompleted: true,
                profileCleanupCompleted: true,
                profileDeleted: false
            )
        }
        guard instance.launcherKind == .managed,
              instance.profileOwnership == .managed else {
            throw AppProfileManagerError.externalInstance
        }
        guard allowStale || maintenanceHealth(for: instance) == .missingData else {
            throw AppProfileManagerError.forgetUnavailable
        }
        var updated = config
        updated.instances.removeAll { $0.id == instanceID }
        guard persist(updated) else {
            throw AppProfileManagerError.persistenceFailed
        }
        if instance.storage == .vault {
            updateVaultManifest(config: updated)
        }
        var launcherCleanupCompleted = true
        do {
            if let staged = try generator.stageLauncherRemoval(for: instance) {
                try generator.commitLauncherRemoval(staged, preserveCustomIcon: false)
            }
        } catch {
            launcherCleanupCompleted = false
        }
        generator.removeHomeSymlinks(for: instanceID, storage: instance.storage)
        return AppProfileRemovalResult(
            config: updated,
            launcherCleanupCompleted: launcherCleanupCompleted,
            profileCleanupCompleted: true,
            profileDeleted: false
        )
    }

    /// Read-only reconciliation of the Klik PRO data roots against the config
    /// and the vault manifest (spec §5). Returns record-less UUID data roots:
    /// marker-owned ones are `.orphanedData` (reclaimable), markerless ones are
    /// `.needsManualReview` (surfaced only). Never touches data (I5). The
    /// fail-closed *in-use* protection is enforced at removal time by the
    /// exclusive per-instance lock, not here — listing a running profile is
    /// harmless because `reclaimData` refuses it.
    func scanOrphans(config: KlikProConfig) -> [OrphanFinding] {
        let recordIDs = Set(config.instances.map { $0.id })
        let manifestIDs: Set<UUID> = {
            guard let vaultRoot = generator.vaultRootURL,
                  let manifest = VaultManifest.read(vaultRoot: vaultRoot) else { return [] }
            return Set(manifest.instances.map { $0.id })
        }()
        var findings: [OrphanFinding] = []
        for candidate in generator.scanProfileDataCandidates() {
            guard !recordIDs.contains(candidate.instanceID),
                  !manifestIDs.contains(candidate.instanceID) else { continue }
            let artifacts = artifactPlan(
                instanceID: candidate.instanceID,
                storage: candidate.storage
            )
            let paths = artifacts.map { $0.url }
            let size = paths.reduce(Int64(0)) { $0 + generator.dataSize(at: $1) }
            findings.append(OrphanFinding(
                instanceID: candidate.instanceID,
                storage: candidate.storage,
                state: candidate.markerPresent ? .orphanedData : .needsManualReview,
                dataPaths: paths,
                sizeBytes: size,
                markerPresent: candidate.markerPresent
            ))
        }
        return findings.sorted {
            $0.instanceID.uuidString < $1.instanceID.uuidString
        }
    }

    /// The UUIDs of all profiles Klik PRO still tracks — config records plus any
    /// vault-manifest entries — so a leftover scan never flags a live profile.
    private func activeInstanceIDs(config: KlikProConfig) -> Set<UUID> {
        var ids = Set(config.instances.map { $0.id })
        if let vaultRoot = generator.vaultRootURL,
           let manifest = VaultManifest.read(vaultRoot: vaultRoot) {
            ids.formUnion(manifest.instances.map { $0.id })
        }
        return ids
    }

    /// Deep scan for orphaned launcher/metadata leftovers (custom-icon copies,
    /// lock files, generated launcher bundles) whose UUID no longer maps to a
    /// tracked profile. Read-only. Orphaned data folders are surfaced separately
    /// by `scanOrphans`.
    func scanLauncherLeftovers(config: KlikProConfig) -> [LauncherGenerator.LauncherLeftover] {
        generator.scanLauncherLeftovers(activeIDs: activeInstanceIDs(config: config))
    }

    /// Removes one scanned launcher/metadata leftover (ownership re-validated by
    /// the generator immediately before the op).
    @discardableResult
    func removeLauncherLeftover(
        _ leftover: LauncherGenerator.LauncherLeftover,
        mode: DataRemovalMode
    ) throws -> URL? {
        try generator.removeLauncherLeftover(leftover, mode: mode)
    }

    /// Best-effort Launch Services cleanup for a removed managed launcher path,
    /// so Launchpad and Spotlight drop the stale entry after Delete Data / Remove.
    func unregisterLauncherFromLaunchServices(at url: URL) {
        generator.unregisterLauncherFromLaunchServices(at: url)
    }

    /// Builds a `DataRemovalTarget` for an existing config record (direct delete
    /// on a visible maintenance row). Only artifacts that actually exist on disk
    /// are included.
    func dataRemovalTarget(for instance: AppProfileInstance) -> DataRemovalTarget {
        let artifacts = artifactPlan(instanceID: instance.id, storage: instance.storage)
        return DataRemovalTarget(
            instanceID: instance.id,
            storage: instance.storage,
            artifacts: artifacts,
            sizeBytes: artifacts.reduce(Int64(0)) { $0 + generator.dataSize(at: $1.url) },
            hasConfigRecord: true
        )
    }

    /// Builds a `DataRemovalTarget` for a record-less orphan finding.
    func dataRemovalTarget(for orphan: OrphanFinding) -> DataRemovalTarget {
        let artifacts = artifactPlan(instanceID: orphan.instanceID, storage: orphan.storage)
        return DataRemovalTarget(
            instanceID: orphan.instanceID,
            storage: orphan.storage,
            artifacts: artifacts,
            sizeBytes: orphan.sizeBytes,
            hasConfigRecord: false
        )
    }

    /// The non-overlapping owned-artifact plan (spec §6.5). Vault storage is one
    /// container (`Instances/<UUID>`); Application Support is the independent
    /// `Profiles/<UUID>`, `CodexHomes/<UUID>`, `CustomIcons/<UUID>.icns` roots.
    /// Only existing paths are listed.
    private func artifactPlan(
        instanceID: UUID,
        storage: AppProfileStorage
    ) -> [DataRemovalArtifact] {
        let fileManager = FileManager.default
        var plan: [DataRemovalArtifact] = []
        switch storage {
        case .vault:
            if let container = try? generator.vaultInstanceDirectoryURL(for: instanceID),
               fileManager.fileExists(atPath: container.path) {
                plan.append(DataRemovalArtifact(
                    url: container.standardizedFileURL, kind: .vaultContainer
                ))
            }
            // The custom-icon copy lives at the storage-independent App Support
            // path, outside the vault container, so it must be listed explicitly.
            let vaultIcon = generator.customIconURL(for: instanceID).standardizedFileURL
            if fileManager.fileExists(atPath: vaultIcon.path) {
                plan.append(DataRemovalArtifact(url: vaultIcon, kind: .customIcon))
            }
        case .applicationSupport:
            let profile = generator.profileURL(for: instanceID).standardizedFileURL
            if fileManager.fileExists(atPath: profile.path) {
                plan.append(DataRemovalArtifact(url: profile, kind: .profileRoot))
            }
            let codexHome = generator.codexHomeURL(for: instanceID).standardizedFileURL
            if fileManager.fileExists(atPath: codexHome.path) {
                plan.append(DataRemovalArtifact(url: codexHome, kind: .codexHome))
            }
            let icon = generator.customIconURL(for: instanceID).standardizedFileURL
            if fileManager.fileExists(atPath: icon.path) {
                plan.append(DataRemovalArtifact(url: icon, kind: .customIcon))
            }
        }
        return plan
    }

    /// Asserts no artifact path is a duplicate or a prefix of another — an
    /// overlap is a programming error that must abort before any removal.
    private func nonOverlapping(_ artifacts: [DataRemovalArtifact]) -> Bool {
        let paths = artifacts.map { $0.url.standardizedFileURL.path }
        guard Set(paths).count == paths.count else { return false }
        for outer in paths {
            for inner in paths where inner != outer {
                if inner.hasPrefix(outer + "/") { return false }
            }
        }
        return true
    }

    /// Move Data to Trash **or** Permanent delete (spec §6.5 + the owner
    /// permanent-delete override). The only data-removal path. Shared gates
    /// (I6/I9): exclusive per-instance lock (the in-use gate for both record and
    /// orphan targets); a record-bearing target additionally runs the two-pass
    /// fail-closed process scan; each artifact is ownership/path re-validated by
    /// the generator immediately before its op. Artifacts are removed
    /// independently with per-artifact results; a `.trash` op never falls back
    /// to a permanent delete.
    func reclaimData(
        target: DataRemovalTarget,
        config: KlikProConfig,
        mode: DataRemovalMode
    ) throws -> DataRemovalResult {
        guard !target.artifacts.isEmpty else {
            return DataRemovalResult(config: config, perArtifact: [], mode: mode)
        }
        guard nonOverlapping(target.artifacts) else {
            throw AppProfileManagerError.dataRemovalUnavailable
        }
        guard let operationLock = ManagedInstanceLock(
            applicationSupportURL: generator.applicationSupportURL,
            instanceID: target.instanceID,
            mode: .exclusive
        ) else {
            throw AppProfileManagerError.processScanIncomplete
        }
        defer { withExtendedLifetime(operationLock) {} }

        if target.hasConfigRecord {
            guard let instance = config.instances.first(where: { $0.id == target.instanceID }),
                  instance.launcherKind == .managed,
                  instance.profileOwnership == .managed,
                  let profileDirectory = instance.profileDirectory else {
                throw AppProfileManagerError.dataRemovalUnavailable
            }
            let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
                .standardizedFileURL
            let profileURL = URL(fileURLWithPath: profileDirectory, isDirectory: true)
                .standardizedFileURL
            for scanIndex in 0..<2 {
                switch processInspector.profileReferences(
                    sourceBundleURL: sourceURL,
                    profileURL: profileURL
                ) {
                case .incomplete:
                    throw AppProfileManagerError.processScanIncomplete
                case .complete(let pids) where !pids.isEmpty:
                    throw AppProfileManagerError.profileInUse
                case .complete:
                    if scanIndex == 0 { waitBetweenProfileScans() }
                }
            }
        }

        var results: [DataRemovalArtifactResult] = []
        for artifact in target.artifacts {
            do {
                let trashURL = try generator.removeOwnedArtifact(
                    at: artifact.url,
                    kind: artifact.kind,
                    instanceID: target.instanceID,
                    storage: target.storage,
                    mode: mode
                )
                results.append(DataRemovalArtifactResult(
                    url: artifact.url, outcome: .removed(trashURL: trashURL)
                ))
            } catch {
                results.append(DataRemovalArtifactResult(url: artifact.url, outcome: .failed))
            }
        }

        var updated = config
        let removedAll = results.allSatisfy {
            if case .removed = $0.outcome { return true }
            return false
        }
        if target.hasConfigRecord && removedAll {
            let wasVault = config.instances
                .first(where: { $0.id == target.instanceID })?.storage == .vault
            updated.instances.removeAll { $0.id == target.instanceID }
            if persist(updated) {
                generator.removeHomeSymlinks(for: target.instanceID, storage: target.storage)
                if wasVault { updateVaultManifest(config: updated) }
                generator.removeManagedInstanceLock(for: target.instanceID)
            } else {
                updated = config
            }
        }
        return DataRemovalResult(config: updated, perArtifact: results, mode: mode)
    }

    /// Repairs derived lifecycle state from the persisted config. This is safe
    /// to run repeatedly: config remains the source of truth, archived launchers
    /// are removed without touching profile data or custom icons, and vault.json
    /// is rewritten from the current rows when a vault is configured.
    @discardableResult
    func reconcileDerivedState(config: KlikProConfig) -> Bool {
        var complete = true
        for instance in config.instances where
            instance.state == .archived
                && instance.launcherKind == .managed
                && instance.profileOwnership == .managed {
            do {
                if let staged = try generator.stageLauncherRemoval(for: instance) {
                    try generator.commitLauncherRemoval(staged, preserveCustomIcon: true)
                }
            } catch {
                complete = false
            }
            generator.removeHomeSymlinks(for: instance.id, storage: instance.storage)
        }
        if config.instances.contains(where: { $0.storage == .vault }) {
            complete = updateVaultManifest(config: config) && complete
        }
        return complete
    }

    /// The launcher is first moved to a hidden UUID-keyed staging path. A failed
    /// config write restores it; a successful write commits deletion. M1 deliberately
    /// retains the profile directory and its data.
    func remove(
        instanceID: UUID,
        config: KlikProConfig,
        deleteProfileData: Bool = false
    ) throws -> AppProfileRemovalResult {
        guard let instance = config.instances.first(where: { $0.id == instanceID }) else {
            return AppProfileRemovalResult(
                config: config,
                launcherCleanupCompleted: true,
                profileCleanupCompleted: true,
                profileDeleted: false
            )
        }
        guard instance.launcherKind == .managed,
              instance.profileOwnership == .managed else {
            throw AppProfileManagerError.externalInstance
        }
        let operationLock: ManagedInstanceLock?
        if deleteProfileData {
            operationLock = ManagedInstanceLock(
                applicationSupportURL: generator.applicationSupportURL,
                instanceID: instance.id,
                mode: .exclusive
            )
            guard operationLock != nil else {
                throw AppProfileManagerError.processScanIncomplete
            }
        } else {
            operationLock = nil
        }
        defer { withExtendedLifetime(operationLock) {} }

        let stagedRemoval: ManagedLauncherRemoval?
        do {
            stagedRemoval = try generator.stageLauncherRemoval(for: instance)
        } catch {
            throw AppProfileManagerError.launcherCleanupFailed
        }

        var stagedProfileRemoval: ManagedProfileRemoval?
        if deleteProfileData {
            guard let profileDirectory = instance.profileDirectory else {
                if let stagedRemoval { try? generator.rollbackLauncherRemoval(stagedRemoval) }
                throw AppProfileManagerError.profileCleanupFailed
            }
            let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
                .standardizedFileURL
            let profileURL = URL(fileURLWithPath: profileDirectory, isDirectory: true)
                .standardizedFileURL
            for scanIndex in 0..<2 {
                switch processInspector.profileReferences(
                    sourceBundleURL: sourceURL,
                    profileURL: profileURL
                ) {
                case .incomplete:
                    if let stagedRemoval { try? generator.rollbackLauncherRemoval(stagedRemoval) }
                    throw AppProfileManagerError.processScanIncomplete
                case .complete(let pids) where !pids.isEmpty:
                    if let stagedRemoval { try? generator.rollbackLauncherRemoval(stagedRemoval) }
                    throw AppProfileManagerError.profileInUse
                case .complete:
                    if scanIndex == 0 { waitBetweenProfileScans() }
                }
            }
            do {
                stagedProfileRemoval = try generator.stageProfileRemoval(for: instance)
            } catch {
                if let stagedRemoval { try? generator.rollbackLauncherRemoval(stagedRemoval) }
                throw AppProfileManagerError.profileCleanupFailed
            }
        }
        var updated = config
        updated.instances.removeAll { $0.id == instanceID }
        guard persist(updated) else {
            if let stagedProfileRemoval {
                try? generator.rollbackProfileRemoval(stagedProfileRemoval)
            }
            if let stagedRemoval {
                try? generator.rollbackLauncherRemoval(stagedRemoval)
            }
            throw AppProfileManagerError.persistenceFailed
        }
        // The row is gone, so its visible home symlink goes too. The sibling
        // home itself keeps M1's retain-for-recovery behavior.
        generator.removeHomeSymlinks(for: instanceID, storage: instance.storage)
        generator.removeManagedInstanceLock(for: instanceID)
        if instance.storage == .vault {
            updateVaultManifest(config: updated)
        }
        guard let stagedRemoval else {
            if let stagedProfileRemoval {
                do {
                    try generator.commitProfileRemoval(stagedProfileRemoval)
                    return AppProfileRemovalResult(
                        config: updated,
                        launcherCleanupCompleted: true,
                        profileCleanupCompleted: true,
                        profileDeleted: true
                    )
                } catch {
                    return AppProfileRemovalResult(
                        config: updated,
                        launcherCleanupCompleted: true,
                        profileCleanupCompleted: false,
                        profileDeleted: false
                    )
                }
            }
            return AppProfileRemovalResult(
                config: updated,
                launcherCleanupCompleted: true,
                profileCleanupCompleted: true,
                profileDeleted: false
            )
        }
        var launcherCleanupCompleted = true
        do {
            try generator.commitLauncherRemoval(stagedRemoval)
        } catch {
            launcherCleanupCompleted = false
        }
        var profileCleanupCompleted = true
        var profileDeleted = false
        if let stagedProfileRemoval {
            do {
                try generator.commitProfileRemoval(stagedProfileRemoval)
                profileDeleted = true
            } catch {
                profileCleanupCompleted = false
            }
        }
        return AppProfileRemovalResult(
            config: updated,
            launcherCleanupCompleted: launcherCleanupCompleted,
            profileCleanupCompleted: profileCleanupCompleted,
            profileDeleted: profileDeleted
        )
    }

    private func managedInstance(
        app: InstalledApp,
        candidate: AppProfileCandidate,
        ruleID: String,
        instanceID: UUID,
        label: String,
        storage: AppProfileStorage = .applicationSupport,
        environmentOverrides: [String: String]
    ) throws -> AppProfileInstance {
        AppProfileInstance(
            id: instanceID,
            label: String(label.prefix(80)),
            launcherKind: .managed,
            launcherPath: generator.launcherURL(
                for: instanceID,
                label: String(label.prefix(80))
            ).path,
            profileDirectory: try generator.profileURL(for: instanceID, storage: storage).path,
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL.path
            ),
            storage: storage,
            environmentOverrides: environmentOverrides,
            pinToMenuBar: false,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0,
                    keyDisplay: "A",
                    command: false,
                    option: false,
                    control: true,
                    shift: false
                )
            ),
            mouseButton: nil,
            lastDetectedEngine: candidate.engine,
            lastVerifiedAppVersion: app.version,
            lastVerifiedTeamIdentifier: app.teamIdentifier,
            compatibilityRuleID: ruleID
        )
    }

    /// Launch-time healing (2026-07-19 owner decision follow-up): brings
    /// existing managed instances up to their rule's CURRENT required
    /// environment — pre-creating the sibling home, rewriting the launcher's
    /// baked payload, and updating the stored environment — and (re)creates
    /// their visible home symlink. Profile data is never moved, deleted, or
    /// regenerated, so healing is safe for instances that are currently in
    /// use. Idempotent: an already-healed config is returned unchanged and
    /// nothing is persisted. Every step is per-instance non-fatal.
    func healManagedInstances(config: KlikProConfig) -> KlikProConfig {
        var updated = config
        var changed = false
        for index in updated.instances.indices {
            let instance = updated.instances[index]
            guard instance.state == .active,
                  instance.launcherKind == .managed,
                  instance.profileOwnership == .managed,
                  let ruleID = instance.compatibilityRuleID,
                  let rule = registry.rule(withID: ruleID) else {
                continue
            }
            // Existing `.applicationSupport` instances resolve through the
            // unchanged default derivation and hit the identical pre-vault
            // path below. `.vault` instances re-derive from the vault's
            // CURRENT root — a moved vault heals its baked paths here — and
            // are skipped fail-safe while that root is unconfigured/absent.
            guard let derivedProfile = try? generator.profileURL(
                for: instance.id,
                storage: instance.storage
            ), let derived = try? ruleResolvedEnvironment(
                ruleID: ruleID,
                instanceID: instance.id,
                storage: instance.storage,
                overriding: instance.environmentOverrides
            ) else {
                continue
            }
            let profileMoved = instance.profileDirectory != derivedProfile.path
            if derived != instance.environmentOverrides || profileMoved {
                guard generator.ensureCodexHome(
                    for: instance.id,
                    environment: derived,
                    storage: instance.storage
                ) else {
                    continue
                }
                var healed = instance
                healed.profileDirectory = derivedProfile.path
                healed.environmentOverrides = derived
                guard (try? generator.updateEnvironment(for: healed)) != nil else {
                    continue
                }
                // A moved vault leaves `~` links aimed at the old location.
                // They are destination-verified against the previously stored
                // home before removal, then recreated at the current path.
                if profileMoved, instance.storage == .vault,
                   let previousProfile = instance.profileDirectory {
                    let previousHome = URL(fileURLWithPath: previousProfile, isDirectory: true)
                        .deletingLastPathComponent()
                        .appendingPathComponent("config-home", isDirectory: true)
                    generator.removeHomeSymlinks(withDestination: previousHome)
                }
                updated.instances[index] = healed
                changed = true
            }
            if rule.homeSymlinkPrefix != nil {
                createHomeSymlinkIfRuleRequests(for: updated.instances[index])
            }
            // Upgrade the launcher's embedded runner in place when an older
            // Klik PRO generated it, so runner-side fixes (e.g. reopening the
            // running instance instead of spawning a duplicate) reach existing
            // profiles from every launch surface. Idempotent, best-effort, and
            // never touches profile data — so it stays outside the `changed`
            // gate below (a pure filesystem refresh, not a config change).
            _ = try? generator.refreshLauncherRuntimeIfStale(for: updated.instances[index])
        }
        guard changed else { return updated }
        guard persist(updated) else { return config }
        return updated
    }

    /// Adopt / recovery (RFC §5.3–5.4): re-adopts a located vault by reading
    /// its manifest and regenerating every ephemeral artifact — launcher,
    /// visible home symlink, baked isolation env — against the vault's
    /// CURRENT absolute path (portability invariant; no baked path is ever
    /// trusted). A folder without a valid `vault.json` is refused outright,
    /// so arbitrary or foreign folders are never adopted. Existing config
    /// rows are merged untouched; their data is never written to.
    func adoptVault(config: KlikProConfig) throws -> VaultAdoptionResult {
        guard generator.vaultRootURL != nil else {
            throw AppProfileManagerError.vaultUnavailable
        }
        guard let vaultRoot = generator.vaultRootURL,
              let manifest = VaultManifest.read(vaultRoot: vaultRoot) else {
            throw AppProfileManagerError.vaultManifestInvalid
        }
        var updated = config
        var adopted: [AppProfileInstance] = []
        var skipped: [UUID] = []
        for record in manifest.instances {
            // An id already in the config is an existing instance: untouched.
            if updated.instances.contains(where: { $0.id == record.id }) { continue }
            // The rule must still exist, but the manifest's cached
            // homeSymlinkPrefix is deliberately NOT part of the gate: it is
            // convenience only, and createHomeSymlinkIfRuleRequests re-derives
            // the current prefix from the rule below. Gating on the cached
            // value would make every vault written before a future dot-folder
            // rename silently un-adoptable — the exact recovery this exists for.
            guard registry.rule(withID: record.compatibilityRuleID) != nil else {
                skipped.append(record.id)
                continue
            }
            let sourceURL = URL(fileURLWithPath: record.sourceBundleURL, isDirectory: true)
                .standardizedFileURL
            guard let current = inspectApplication(sourceURL),
                  current.bundleURL.standardizedFileURL == sourceURL,
                  current.bundleIdentifier == record.sourceBundleIdentifier else {
                skipped.append(record.id)
                continue
            }
            let currentCandidate = candidate(for: current)
            guard currentCandidate.canCreate,
                  currentCandidate.eligibility.compatibilityRuleID
                    == record.compatibilityRuleID else {
                skipped.append(record.id)
                continue
            }
            // Labels share one launcher namespace with existing rows; a
            // collision is skipped rather than renaming the vault's data.
            guard !updated.instances.contains(where: {
                $0.label.caseInsensitiveCompare(record.label) == .orderedSame
            }) else {
                skipped.append(record.id)
                continue
            }
            guard let environment = try? ruleResolvedEnvironment(
                ruleID: record.compatibilityRuleID,
                instanceID: record.id,
                storage: .vault,
                overriding: [:]
            ), var instance = try? managedInstance(
                app: current,
                candidate: currentCandidate,
                ruleID: record.compatibilityRuleID,
                instanceID: record.id,
                label: record.label,
                storage: .vault,
                environmentOverrides: environment
            ) else {
                skipped.append(record.id)
                continue
            }
            // The vault must actually hold this instance's owned data
            // (matching `Instances/<UUID>/user-data` + UUID ownership marker).
            guard (try? generator.validatedProfileURL(for: instance)) != nil else {
                skipped.append(record.id)
                continue
            }
            instance.state = record.archived ? .archived : .active
            instance.menuColor = record.menuColor
            if record.customIcon {
                guard generator.restoreCustomIconFromVault(for: instance) else {
                    skipped.append(record.id)
                    continue
                }
            }
            if instance.state == .archived {
                instance.pinToMenuBar = false
                instance.iconPath = generator.hasCustomIcon(for: instance.id)
                    ? generator.customIconURL(for: instance.id).path
                    : nil
                updated.instances.append(instance)
                adopted.append(instance)
                continue
            }
            if (try? generator.validatedLauncherURL(for: instance)) != nil {
                // A surviving launcher is never trusted: its baked payload is
                // rewritten against the vault's current path.
                guard (try? generator.updateEnvironment(for: instance)) != nil else {
                    skipped.append(record.id)
                    continue
                }
                let iconURL = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
                    .appendingPathComponent("Contents/Resources/AppIcon.icns")
                instance.iconPath = FileManager.default.fileExists(atPath: iconURL.path)
                    ? iconURL.path
                    : nil
            } else {
                guard let materialization = try? generator.regenerateLauncher(
                    instance: instance,
                    sourceApp: current
                ) else {
                    skipped.append(record.id)
                    continue
                }
                instance.iconPath = materialization.iconURL?.path
            }
            createHomeSymlinkIfRuleRequests(for: instance)
            updated.instances.append(instance)
            adopted.append(instance)
        }
        guard appProfileAssignmentsAreValid(updated) else {
            throw AppProfileManagerError.invalidAssignments
        }
        guard adopted.isEmpty || persist(updated) else {
            throw AppProfileManagerError.persistenceFailed
        }
        return VaultAdoptionResult(
            config: updated,
            adopted: adopted,
            skippedInstanceIDs: skipped
        )
    }

    /// Creates the instance's visible home symlink when its compiled-in rule
    /// declares a dot-folder prefix (2026-07-19 owner decision). Non-fatal by
    /// design: profile creation never fails over a missing convenience link.
    private func createHomeSymlinkIfRuleRequests(for instance: AppProfileInstance) {
        guard let ruleID = instance.compatibilityRuleID,
              let prefix = registry.rule(withID: ruleID)?.homeSymlinkPrefix else {
            return
        }
        generator.createHomeSymlink(
            for: instance.id,
            environment: instance.environmentOverrides,
            preferredName: LauncherGenerator.homeSymlinkName(
                prefix: prefix,
                label: instance.label
            ),
            storage: instance.storage
        )
    }

    /// New instances follow the config's data root (plan §5.1): nil means the
    /// unchanged Application Support layout. A configured vault must match the
    /// generator's wired vault root and pass the fail-closed location gate;
    /// any mismatch disables creation rather than silently falling back.
    private func newInstanceStorage(for config: KlikProConfig) throws -> AppProfileStorage {
        guard let dataRoot = config.dataRoot else { return .applicationSupport }
        let requested = URL(fileURLWithPath: dataRoot, isDirectory: true).standardizedFileURL
        guard let vaultRoot = generator.vaultRootURL,
              vaultRoot.path == requested.path,
              vaultPathRejectionReason(dataRoot) == nil else {
            throw AppProfileManagerError.creationDisabled(
                "The configured data folder is unavailable or invalid."
            )
        }
        return .vault
    }

    /// Rewrites the vault's manifest from the current config whenever a vault
    /// instance is created, renamed, or removed. The write is atomic; a
    /// read-only or absent volume makes it a surfaced no-op, never a failure
    /// of the in-app operation itself. No absolute paths are persisted — the
    /// rule id is the re-derivable key every adopt resolves fresh.
    @discardableResult
    private func updateVaultManifest(config: KlikProConfig) -> Bool {
        guard let vaultRoot = generator.vaultRootURL else { return false }
        for instance in config.instances where instance.storage == .vault {
            _ = generator.synchronizeCustomIconToVault(for: instance)
        }
        let records = config.instances
            .filter {
                $0.storage == .vault
                    && $0.launcherKind == .managed
                    && $0.profileOwnership == .managed
            }
            .map { instance in
                VaultManifestInstanceRecord(
                    id: instance.id,
                    label: instance.label,
                    sourceBundleIdentifier: instance.source.bundleIdentifier,
                    sourceTeamIdentifier: instance.lastVerifiedTeamIdentifier,
                    sourceBundleURL: instance.source.bundleURL,
                    compatibilityRuleID: instance.compatibilityRuleID ?? "",
                    homeSymlinkPrefix: instance.compatibilityRuleID.flatMap {
                        registry.rule(withID: $0)?.homeSymlinkPrefix
                    },
                    archived: instance.state == .archived,
                    menuColor: instance.menuColor,
                    customIcon: generator.hasVaultCustomIcon(for: instance.id)
                )
            }
        return VaultManifest(
            schemaVersion: VaultManifest.currentSchemaVersion,
            instances: records
        ).write(to: vaultRoot)
    }

    /// Derives the Verified rule's required environment for one instance and
    /// merges it OVER any caller-supplied overrides: a caller (UI, tests, the
    /// evidence harness) can extend the environment but never weaken a
    /// rule-owned isolation key.
    private func ruleResolvedEnvironment(
        ruleID: String,
        instanceID: UUID,
        storage: AppProfileStorage = .applicationSupport,
        overriding caller: [String: String]
    ) throws -> [String: String] {
        guard let rule = registry.rule(withID: ruleID) else {
            throw AppProfileManagerError.creationDisabled(
                "The matched compatibility rule is no longer present."
            )
        }
        let derived: [String: String]
        do {
            derived = try rule.resolvedEnvironment(
                profileDirectory: generator.profileURL(for: instanceID, storage: storage).path,
                codexHomeDirectory: generator.codexHomeURL(for: instanceID, storage: storage).path
            )
        } catch {
            throw AppProfileManagerError.creationDisabled(
                "The compatibility rule's required environment could not be resolved."
            )
        }
        return caller.merging(derived) { _, ruleValue in ruleValue }
    }

    private func verifiedSource(for instance: AppProfileInstance) throws -> InstalledApp {
        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        guard let current = inspectApplication(sourceURL),
              current.bundleURL.standardizedFileURL == sourceURL,
              current.bundleIdentifier == instance.source.bundleIdentifier else {
            throw AppProfileManagerError.sourceChanged
        }
        let currentCandidate = candidate(for: current)
        guard currentCandidate.canCreate,
              currentCandidate.eligibility.compatibilityRuleID == instance.compatibilityRuleID else {
            throw AppProfileManagerError.creationDisabled(currentCandidate.eligibility.reason)
        }
        return current
    }

    private func sameSource(_ current: InstalledApp, _ selected: InstalledApp) -> Bool {
        current.bundleURL.standardizedFileURL == selected.bundleURL.standardizedFileURL
            && current.bundleIdentifier == selected.bundleIdentifier
            && current.teamIdentifier == selected.teamIdentifier
            && current.version == selected.version
            && current.buildVersion == selected.buildVersion
    }
}

// MARK: - Data-root wiring (Durable Data Vault, Phase 2)

/// Builds the launcher generator the production app should use for a given
/// `config.dataRoot`. This is the single wiring decision that turns the dormant
/// Phase 1 backend on: a `nil`, malformed, or fail-closed-rejected data root
/// yields a **no-vault** generator (no `vaultRootURL`), so `newInstanceStorage`
/// returns `.applicationSupport` and behavior stays byte-for-byte the pre-vault
/// app. Only a data root that passes `vaultPathRejectionReason` wires the vault
/// root, and it is wired at exactly `config.dataRoot` — the equality
/// `newInstanceStorage` requires before it will ever create a `.vault` instance.
/// Isolated as a free function (no AppKit) so the decision is unit-testable.
func makeLauncherGenerator(forDataRoot dataRoot: String?) -> LauncherGenerator {
    guard let dataRoot, vaultPathRejectionReason(dataRoot) == nil else {
        return LauncherGenerator()
    }
    return LauncherGenerator(
        vaultRootURL: URL(fileURLWithPath: dataRoot, isDirectory: true)
    )
}

/// The production `AppProfileManager` for a given `config.dataRoot`, built on the
/// generator `makeLauncherGenerator(forDataRoot:)` selects. Callers rebuild the
/// manager through this whenever the user picks or clears the vault folder so the
/// generator's wired root and `config.dataRoot` never drift apart.
func makeAppProfileManager(forDataRoot dataRoot: String?) -> AppProfileManager {
    AppProfileManager(generator: makeLauncherGenerator(forDataRoot: dataRoot))
}
