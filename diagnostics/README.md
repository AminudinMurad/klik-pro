# Mouse Control Diagnostics

Three throwaway command-line tools for working out how a given mouse's
controls actually behave. None is part of the shipped app. Originally
built to answer one question about the thumb wheel — **what does macOS
actually report when you tilt/scroll it, and is it a clean discrete signal
or a noisy continuous one?** — `scroll-probe` also watches for `keyDown`/
`keyUp`, so it doubles as a way to check whether another control emits a plain
keystroke on its own (the tested Gesture button emits Command-Tab), or needs a
vendor driver running to do anything at all. For the tested MX Master 3
Mac, Gesture uses a device-scoped Tab-to-F20 sentinel so keyboard Command-Tab remains
untouched.

## Before you start

Quit any vendor mouse-configuration app (e.g. a driver/settings suite) if
one is running — those can grab the raw input stream and cause contention
with what these probes see.

## 1. `scroll-probe` — tests the CGEventTap scroll-delta path

```zsh
swiftc scroll-probe.swift -o scroll-probe
./scroll-probe
```

Grant Accessibility permission when prompted (System Settings -> Privacy &
Security -> Accessibility -> allow the terminal app you're running this
from). Re-run after granting.

Move the main wheel, then tilt/scroll the thumb wheel, then click the side
buttons, then press any other control **one at a time** (isolating each one
makes the output much easier to read). Watch for lines starting with
`HSCROLL`, `BUTTON`, or `KEY`.

**What to look for:**
- Do `HSCROLL` lines appear at all when you tilt the thumb wheel? If nothing
  prints, this path may not see it directly (try `hid-report-probe` instead).
- `continuous=1` means macOS treats it like a trackpad/precision device
  (smooth stream of small deltas). `continuous=0` means discrete
  notch-based ticks (closer to a traditional wheel).
- Look at the `gap=` values between consecutive `HSCROLL` lines for one
  physical click of the wheel — if you get a burst of many events with tiny
  gaps (<0.02s) per click, you'll need a delta-accumulation + threshold
  approach rather than a naive "any nonzero delta = one action" rule.
- A control that produces neither a `BUTTON` nor a `KEY DOWN`/`KEY UP` line
  when pressed isn't reaching the OS as a discrete event at all — it likely
  needs the mouse's own vendor software running to do anything.
- A control that produces a `KEY DOWN`/`KEY UP` line tells you the keyCode and
  modifiers its firmware emits. Do not intercept it unless you also have a reliable
  way to distinguish the mouse event from the same physical-keyboard shortcut;
  otherwise leave that control native.

## 2. `hid-report-probe` — tests the raw HID path

```zsh
swiftc hid-report-probe.swift -o hid-report-probe
./hid-report-probe
```

This one needs **Input Monitoring** permission (System Settings -> Privacy &
Security -> Input Monitoring), separate from Accessibility. Grant it to the
terminal app you're running this from, then re-run.

Move the main wheel, tilt the thumb wheel, click side buttons, and watch the
raw byte dumps.

**What to look for:**
- Does a device match at startup (prints "Matched device: ..." with a
  product name)? If nothing matches, the mouse may be connected in a mode
  (e.g. via a different Bluetooth/receiver path) this vendor-ID filter
  doesn't catch.
- Compare the byte patterns between a vertical scroll, a thumb-wheel tilt,
  and a button click. If the thumb wheel produces a **distinctly different,
  short, repeatable report** (rather than a long burst of near-identical
  reports), that's evidence it arrives as something closer to a discrete
  event at the HID layer.

## 3. `gesture-probe` — proves mouse/keyboard isolation

```zsh
swiftc gesture-probe.swift -o gesture-probe
./gesture-probe
```

This combined listen-only probe matches the MX Master 3 Mac (`0x046D:0xB023`) at
the raw-HID layer and observes normalized Command-Tab events at the CGEvent layer.
Press the physical Gesture Button once, then keyboard Command-Tab once. Before the
device-scoped sentinel is applied, expected output classifies the first as
`MOUSE GESTURE` and the second as `KEYBOARD/OTHER`. It was used to measure the raw
mouse report arriving about 10.6 ms before the corresponding CG event; production
uses the deterministic F20 sentinel rather than this timing window.

## Reporting back

Paste the console output from the relevant tools (a few seconds of idle, one
vertical scroll, one thumb-wheel tilt, one button click each) to compare
notes when adapting the mappings in `Sources/` for a new mouse.
