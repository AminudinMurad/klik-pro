# Klik PRO 1.2.9 (build 13)

Klik PRO 1.2.9 corrects Deep Scan for App Profile data left in a previously used
durable Data Folder.

## Deep Scan correction

- **Previously used Data Folders remain discoverable:** clearing the active Data
  Folder no longer erases the validated root from Deep Scan's bounded allow-list.
- **Safe upgrade path:** when an older configuration has already lost that pointer,
  Deep Scan asks the user to choose the previous Klik PRO Data Folder. The scan is
  read-only and does not adopt the folder or change storage for new profiles.
- **Markerless folders are reported:** UUID-named `Instances` folders without a Klik
  PRO ownership marker appear as **Needs manual review** instead of a false clean
  result.
- **Visible Finder action:** manual-review results provide **Reveal in Finder** in
  both the scan result and App Profile Maintenance.
- **No destructive expansion:** markerless folders remain excluded from Move to
  Trash and Delete Permanently. Klik PRO never deletes them automatically.

## Download

The DMG is recommended. A universal ZIP containing the same Apple Silicon and Intel
app is also attached. Klik PRO is ad-hoc signed and not notarized, so follow the
documented first-launch Gatekeeper steps or use the verified Terminal installer.

After updating, macOS may require Klik PRO Helper to be removed and re-added under
System Settings > Privacy & Security > Accessibility.
