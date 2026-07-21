# Klik PRO 1.2.1 (build 5)

Klik PRO 1.2.1 introduces a safer way to understand and maintain App Profiles.
Instead of leaving a manually removed launcher as an unexplained stale row, Advanced
now identifies what is healthy, what can be repaired, what is archived, and when the
underlying profile data is genuinely missing.

![Klik PRO 1.2.1 App Profile Maintenance](https://raw.githubusercontent.com/AminudinMurad/klik-pro/v1.2.1/assets/screenshot-advanced.png)

## What’s new

- **Health at a glance:** every managed App Profile is classified as Healthy,
  Missing Launcher, Missing Data, or Archived.
- **Repair Launcher:** rebuild a missing generated app without changing the profile’s
  UUID, login, settings, or custom icon.
- **Archive without deleting:** deactivate a profile and remove its launcher while
  preserving its data, assignment choices, identity, and artwork.
- **Restore later:** regenerate an archived profile with the same identity after Klik
  PRO verifies its data and assignment safety.
- **Stronger durable recovery:** schema 12 and vault manifest v2 preserve lifecycle,
  menu colour, and custom-icon intent. A durable icon copy travels with vault data.
- **Automatic reconciliation:** Klik PRO repairs derived manifest state and completes
  interrupted archive cleanup at launch without modifying login data.

## Safety boundary

This is intentionally a non-destructive release. It does not permanently delete App
Profile data. If owned data is missing, Klik PRO reports it and fails closed rather
than guessing, silently recreating it, or deleting another path.

## Download

The DMG is recommended. A universal ZIP containing the same Apple Silicon and Intel
app is also attached. Klik PRO is ad-hoc signed and not notarized, so follow the
documented first-launch Gatekeeper steps or use the verified Terminal installer.

Please test Repair, Archive, and Restore with your own App Profiles and share what you
find through [GitHub Issues](https://github.com/AminudinMurad/klik-pro/issues).
