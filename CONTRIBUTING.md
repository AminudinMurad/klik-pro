# Contributing to Klik PRO

Thanks for your interest! Klik PRO is a small, single-maintainer macOS utility
(Swift + AppKit/Carbon, no dependencies, GPL-3.0-licensed). Issues and pull requests
are welcome.

## Ground rules

- Be respectful — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- Open an issue before a large change so we can agree on the approach.
- Keep changes focused; match the style of the surrounding code.
- Found a security issue? Please **don't** open a public issue — see
  [SECURITY.md](SECURITY.md).

## Project layout

| Path | Purpose |
|---|---|
| `Sources/KlikProApp.swift` | Settings app (`@main`) — the UI and config editing |
| `Sources/KlikProInput.swift` | Input helper — the CGEvent tap that maps buttons/scroll to combos |
| `Sources/KlikProConfig.swift` | Shared config model + log/config paths (compiled into every binary) |
| `App/`, `LaunchAgents/` | App bundle `Info.plist` and `launchd` plists |
| `assets/`, `docs/`, `diagnostics/` | Artwork, setup docs, and mouse-probing dev tools |
| `Tests/`, `tools/` | Focused regression checks and reproducible build/release tooling |

## Building

Run the repository checks, which compile both executables for Apple Silicon and
Intel with the documented macOS 13 deployment target and run the focused routing test:

```zsh
./tools/check.sh
```

To assemble, sign, and verify the universal release DMG and ZIP:

```zsh
./tools/build-release.sh
```

The full app-bundle → install → Accessibility procedure lives in
[`docs/INSTALL.md`](docs/INSTALL.md). The optional dual-instance feature is
documented in [`docs/SPECIAL_FEATURE.md`](docs/SPECIAL_FEATURE.md).

## Verifying a change

- **Run `./tools/check.sh`** to compile both architectures, validate plists,
  verify the generated device image, and run routing regression checks.
- **For UI changes, render and look — don't rely on compile alone.** Run
  `./tools/render-previews.sh`; it renders both AppKit tabs to the checked-in PNGs
  without Screen Recording permission.
- If a check wasn't run, say "not run" rather than implying it passed.

### Gotcha: the Accessibility grant drops on every rebuild

The input helper is ad-hoc signed, so its code signature changes on each build and
macOS revokes its Accessibility grant. After rebuilding the helper, remove and
re-add it in **System Settings → Privacy & Security → Accessibility**, or mappings
silently stop working. (A settings-app-only change doesn't require this — the helper
binary is untouched.)

## Pull requests

1. Fork and branch from `main`.
2. Make the change; build and verify as above.
3. Describe what you changed and how you tested it. Note anything you couldn't test
   (e.g. hardware you don't have).

## Scope note

Button naming, thumb-wheel behavior, and default shortcuts were tuned against one
specific mouse (see the "Tested with" section of the README). If you're adding
support for a different device, start with the tools in `diagnostics/` to see how
your mouse actually reports to macOS.
