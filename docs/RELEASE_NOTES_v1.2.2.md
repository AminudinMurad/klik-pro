# Klik PRO 1.2.2 (build 6)

Klik PRO 1.2.2 is an important corrective update for anyone using App Profiles with
a selected durable Data Folder. It also completes the maintenance workflow for safely
repairing, archiving, recovering, and deleting managed profile data.

## Important v1.2.1 correction

Klik PRO 1.2.1 generated launchers that incorrectly required the default Application
Support profile path. As a result, newly created profiles stored in a selected durable
Data Folder could fail to launch. Profiles using the default Application Support
location were not affected.

Version 1.2.2 signs the exact validated storage type and profile path into new
launchers. Existing managed launchers are refreshed when used, without moving or
changing their login/profile data.

## Maintenance and recovery

- **Forget stale entries:** remove a record whose profile data is already missing,
  without guessing at or recreating that data.
- **Find leftover data:** identify marker-owned App Profile data that no longer has a
  trustworthy Klik PRO record.
- **Archive and restore:** deactivate a profile without deleting its login data, then
  restore it later with the same identity and custom icon.
- **Safe data removal:** move validated profile data to the macOS Trash by default, or
  choose Delete Permanently after a second warning. Ambiguous, markerless, symlinked,
  or in-use paths fail closed.
- **Clearer wording:** **Remove from Klik PRO** keeps login/profile data on disk;
  **Delete Data** removes the launcher, Klik PRO entry, and validated profile data.
- **Responsive maintenance screen:** profile scanning and health checks no longer
  block ordinary App Profile actions when a durable Data Folder is slow to respond.

## Download

The DMG is recommended. A universal ZIP containing the same Apple Silicon and Intel
app is also attached. Klik PRO is ad-hoc signed and not notarized, so follow the
documented first-launch Gatekeeper steps or use the verified Terminal installer.

After updating, macOS may require Klik PRO Helper to be removed and re-added under
System Settings > Privacy & Security > Accessibility.
