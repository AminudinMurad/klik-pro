# v1.5.1 helper performance baseline

Recorded 2026-07-28 before the first v1.5.1 runtime optimization.

## Environment

- Installed runtime: Klik PRO v1.5.0 build 23
- Development baseline: v1.5.1 build 24, with no runtime changes before recording
- macOS: 26.6 (25G72)
- Xcode: 26.6 (17F113)
- Instruments/xctrace: 16.0 (17F113)
- Target: `klik-pro-input`

The installed build is a valid pre-change baseline because the initial build-24
commit changed metadata, documentation, and tooling but no runtime source.
Trace bundles remain private below the Git-ignored `build/profiles/` directory.

## Idle Time Profiler

Command:

```zsh
./tools/xcode-dev.sh profile "klik-pro-input" "Time Profiler" 15s
```

Trace: `build/profiles/20260728-193255-time-profiler.trace`

The 15.986-second recording contained 11,821 one-millisecond running-thread
samples. The recurring availability refresh dominated the sampled work:

| Stack frame | Samples containing frame |
|---|---:|
| `refreshQuickLaunchAvailability()` | 2,913 |
| `AppProfileRuntime.health(for:)` | 2,909 |
| `AppScanner.inspect(_:)` | 2,901 |
| `SecStaticCodeCheckValidityWithErrors` | 2,855 |

The samples show `AppScanner.inspect(_:)` performing strict source-app
code-signature validation from the helper's five-second availability timer.
Code-signature validation fans out across several worker threads and reads the
source bundle even when no profile file has changed.

## Idle Activity Monitor

Command:

```zsh
./tools/xcode-dev.sh profile "klik-pro-input" "Activity Monitor" 15s
```

Trace: `build/profiles/20260728-193552-activity-monitor.trace`

Activity Monitor counters are cumulative for the process lifetime. Subtracting
the first recorded row from the last over the 15.836-second trace gives:

| Metric | Baseline |
|---|---:|
| CPU time consumed during trace | 11.509 seconds |
| Average CPU capacity | approximately 72.7% of one core |
| Highest reported interval | 366.6% CPU |
| Idle wakeups during trace | 13 |
| Disk reads during trace | 256 KiB |
| Disk writes during trace | 0 bytes |

This is not genuinely idle behavior: the timer runs at five-second intervals and
repeats full managed-profile health and signature validation. A point-in-time
`ps` sample can show 0% between these large bursts, so the interval recording is
the authoritative baseline.

## macOS power-measurement limitation

Xcode 26.6 lists a Power Profiler template, but `xctrace` rejects it on macOS and
reports that it supports only iOS and iPadOS. No unsupported power figure is
claimed here. Activity Monitor CPU time, wakeups, and I/O are used as the macOS
energy proxies, with Time Profiler providing the responsible call stacks.

## Optimization decision

The five-second monitor still needs to notice installed-app, launcher, and profile
availability changes. It does not need to repeat cryptographic identity proof
when those inputs are unchanged.

The v1.5.1 optimization therefore:

1. performs full managed-profile validation at helper startup;
2. polls inexpensive file identity metadata every five seconds;
3. repeats full health/signature validation only when that fingerprint or legacy
   quick-launch availability changes; and
4. keeps `launchOrFocus` validation unchanged, so every managed action remains
   fail-closed even if a filesystem metadata edge is missed.

An after-change Instruments comparison requires running a private build-24 helper.
Do not install or distribute that build without owner testing and approval.
