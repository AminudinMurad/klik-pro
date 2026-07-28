# Xcode development and performance profiling

Klik PRO keeps its checked-in shell build as the source of truth. This avoids a
second set of target membership, signing, helper-embedding, and release settings
drifting inside an Xcode project. The full Xcode installation is still useful for
its macOS SDK, source editor, debugger attachment, and Instruments.

The active command-line developer directory may still point at the standalone
Command Line Tools after Xcode is installed. The repository helper automatically
uses `/Applications/Xcode.app/Contents/Developer` when that happens, without
changing the machine-wide `xcode-select` setting.

## Verify the toolchain

```zsh
./tools/xcode-dev.sh doctor
```

Open the repository as a source folder in Xcode:

```zsh
./tools/xcode-dev.sh open
```

Run the normal checks or release build with Xcode's SDK:

```zsh
./tools/xcode-dev.sh check
./tools/xcode-dev.sh build
```

## Profile the settings app

Open Klik PRO normally, exercise the interaction being investigated, and attach
Time Profiler for 30 seconds:

```zsh
./tools/xcode-dev.sh profile
```

Other useful recordings include:

```zsh
./tools/xcode-dev.sh profile "Klik PRO" "Allocations" 30s
./tools/xcode-dev.sh profile "Klik PRO" "Leaks" 30s
./tools/xcode-dev.sh profile-launch
```

Traces are written below `build/profiles/`, which is ignored by Git. Open the
reported `.trace` file in Instruments and repeat the exact same interaction for
before/after comparisons.

## Profile the always-on helper

The helper process is named `klik-pro-input`. It is the important target for
steady-state CPU and energy work:

```zsh
./tools/xcode-dev.sh profile "klik-pro-input" "Time Profiler" 1m
./tools/xcode-dev.sh profile "klik-pro-input" "Power Profiler" 2m
```

Record an idle baseline first, then a second trace while generating the same mouse
input repeatedly. Optimize only a measured hot path, and confirm the improvement
with the same template, duration, and interaction.

## Debugging notes

- Xcode can attach LLDB to either running process using **Debug → Attach to
  Process by PID or Name**.
- The release builder already uses Swift `-O`. Instruments measurements are more
  useful than changing optimization flags speculatively.
- Rebuilding the ad-hoc-signed helper changes its code signature and can revoke its
  Accessibility grant. Follow the re-grant instructions in `CONTRIBUTING.md`.
- App-launch and first-run traces include one-time setup work. Use an attached
  steady-state trace when evaluating normal background cost.
