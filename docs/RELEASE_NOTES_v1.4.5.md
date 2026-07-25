# Klik PRO 1.4.5

Klik PRO 1.4.5 fixes App Profile data that could not be deleted at all, and tidies
the Advanced tab so the data-folder controls and the cleanup controls sit where you
would look for them.

- **Delete Data works again.** Deleting an App Profile's login data — or leftover
  data with no profile left — failed for every ChatGPT or Claude profile that had
  ever been launched, in both **Move to Trash** and **Delete Permanently**. The first
  time one of these apps runs it writes four links of its own into the profile
  (`SingletonLock`, `SingletonCookie`, `SingletonSocket`, `RunningChromeVersion`), and
  Klik PRO's ownership check refused to remove any profile that contained a link. It
  now allows a profile's own links and still refuses the one shape that matters — a
  link pointing at a folder outside the profile.
- **Deep Scan for Leftovers can finish the job.** The same check blocked the data
  folders Deep Scan found, so a cleanup could remove icons, lock files, and stale Dock
  tiles but always left the profile folders behind.
- **A failure message that is true.** A refused removal used to advise quitting the
  app or restarting macOS. Neither could ever help, because the links are written back
  on the next launch. The message now says what actually happened: Klik PRO could not
  verify the item as its own, or the disk refused.
- **A data folder from the first launch.** First-run onboarding gains a second step:
  **Where your profile logins live**, offering `~/Klik PRO Vault` with **Use This
  Folder** as the default action. Klik PRO creates the folder if it does not exist,
  and from then on new App Profiles are stored there — so logins survive an uninstall
  without ever having to be moved. **Choose Folder…** on the page picks a different
  location (an external disk, for instance), and **Skip for Now** keeps logins inside
  Application Support exactly as before. Nothing is written until the last onboarding
  page, so backing up and changing your mind leaves nothing half-applied.
- **Scan & Import.** **Scan & Adopt** is renamed **Scan & Import** and moves up next
  to **Choose Folder** and **Clear** — all three point Klik PRO at a data folder, so
  they now sit together.
- **Profile Cleanup.** **Deep Scan for Leftovers** moves out of the recovery section
  into its own **Profile Cleanup** section, below **App Profile Maintenance** — the
  profiles you still have above, what removed profiles left behind below.

Nothing outside a profile is removed. A link that resolves to a folder outside the
profile still fails closed and nothing is touched, and a profile's own links move to
the Trash as links, never followed. Your profiles, logins, and button assignments are
unchanged by this release.
