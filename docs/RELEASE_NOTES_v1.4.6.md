# Klik PRO 1.4.6

Klik PRO 1.4.6 adds Gemini to App Profiles — the first app supported that is not
built on Electron — so you can keep several Google accounts signed in side by side,
each with its own chat history.

- **Gemini App Profiles.** Google's Gemini desktop app now appears in the generator
  and can hold as many separate profiles as you have accounts. Every profile keeps its
  own login, cookies, notebooks and chat list, and they all run at the same time in
  their own windows. Tested with four Google accounts open together.

- **Listed as Experimental, on purpose.** Gemini's isolation has been confirmed on
  this machine — logins persist across quitting and relaunching, and each account
  stays independent — but it has not yet been re-checked after a Gemini update, which
  is the second thing Klik PRO requires before calling an app Verified. It will move
  to Verified once Google ships an update and the profile survives it.

- **Logins now stick for Gemini.** Gemini keeps its sign-in in a place that is only
  reachable when the app can also see your login keychain. Without that, it would
  appear to sign in, work normally for the session, and then quietly forget the
  account the moment you quit. Klik PRO now sets each Gemini profile up so the sign-in
  is stored properly the first time.

- **Gemini is isolated without touching the app.** Unlike ChatGPT and Claude, Gemini
  accepts no profile setting on launch, so Klik PRO points its whole storage location
  somewhere per-profile instead. Your `/Applications/Gemini.app` is never copied,
  modified or re-signed, and profiles keep working after Gemini updates itself.

- **Fixed: profile settings could be built with the wrong launch options.** A profile
  was always given the Electron-style data-folder switch, even for an app that does
  not understand it. Profiles now only receive the options their app actually
  supports.

## Notes

Two profiles signed into the **same** Google account will show the same conversations,
because Gemini stores chats on Google's servers rather than on your Mac. App Profiles
separate logins, not the account's own cloud history. Different accounts stay fully
separate.

Gemini profiles share one set of Gemini app preferences — things like window position
and feature toggles. Accounts, chats and logins are not shared.
