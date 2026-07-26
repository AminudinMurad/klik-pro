# Mouse identity and per-device routing proposal

Status: design proposal; no sender-aware event routing has been implemented.

This document consolidates the mouse-profile proposals discussed on 2026-07-26,
including the original public-API design and the later OpenLogi finding. It also
separates what Klik PRO currently does from what the UI may appear to promise.

## 1. Problem statement

Klik PRO can store several sets of mouse mappings, but selecting a stored set is
not the same thing as identifying the physical mouse that produced a click.

The required behavior is:

- Bind one physical mouse to one saved mapping set.
- Let two connected mice use different mappings at the same time.
- Route Middle, Back, Forward, Gesture and supported wheel events using the
  identity of the mouse that generated that event.
- Display a recognizable device name while keeping a stable technical identity
  underneath it.
- Fall back safely when macOS cannot identify the event source.

Example:

```text
Logi M650 middle click  -> M650 assignment  -> Open Claude
HP Mouse middle click   -> HP assignment    -> Open Spotify
Unidentified mouse      -> Default mapping  -> configured fallback/no action
```

Without event-source identification, all mice are handled by the currently
active mapping set. That explains the observed bug where Mouse 2's middle click
used Mouse 1's assignment.

## 2. Terminology and UI meaning

“Mouse Profile” is misleading if the object is only a manually selected set of
mappings. A profile name such as “Work” or “Travel” does not identify hardware.

Recommended terms:

- **Mouse mappings** or **Mapping set**: the saved button and wheel behavior.
- **Assigned mouse**: the optional physical HID identity bound to that set.
- **Active fallback**: the mapping set used when the event source is unavailable
  or unassigned.

If true per-device routing is implemented, “Mouse Profile” becomes defensible,
but “Mouse mappings” is still clearer and avoids confusion with App Profiles.

Renaming a mapping set must not rename the physical device. These are separate
values:

```text
Mapping-set name:  “Office”
Physical device:   “Logi M650”
Stable identity:   VID 046D / PID B02A / serial 9A519428
```

The device picker should never substitute an opaque label such as
`Assigned mouse 046D:…` when a current or cached product name is available.

## 3. Current foundation

Klik PRO already has useful parts of the design:

- `IOHIDManager` enumeration of external mouse-class devices.
- A persisted `MouseDeviceIdentity` containing vendor ID, product ID and an
  optional serial number.
- Up to three independently stored mapping sets.
- A single active mapping set and computed config proxies used by the input
  helper.
- Validation preventing one physical identity from being silently bound to two
  sets.
- A `CGEventTap` that observes and can suppress mouse events.

Device scanning and device-specific event routing are different problems:

```text
Scan:   “Which mice are connected?”
Route:  “Which connected mouse generated this particular event?”
```

Successful scanning alone does not make button routing device-specific.

## 4. Original proposal: public macOS APIs

### 4.1 Simple option: activate on device arrival/removal

Bind a mapping set to a scanned `IOHIDDevice`. Observe device arrival and
removal, then make the newly available device's mapping set active. Klik PRO
already uses a similar arrival observer for its MX Master 3 Gesture setup.

```text
Mouse connects
      |
      v
IOKit arrival observer
      |
      v
Find bound mapping set
      |
      v
Make it the one global active set
```

Advantages:

- Uses public APIs.
- Small, incremental change.
- Appropriate when only one external mouse is used at a time.

Limitations:

- It does not identify the source of each click.
- If two mice remain connected, both still use the same active set.
- Arrival order becomes behavior, which is not a reliable user intention.
- A USB dongle that remains connected can keep a mouse “present” even when the
  physical mouse is switched off.

This is an acceptable compatibility fallback, not a complete solution.

### 4.2 Full public-API option: correlate two event streams

`IOHIDManager` input-value callbacks identify their originating `IOHIDDevice`.
`CGEventTap` supplies the events Klik PRO currently interprets and suppresses.
The earlier full proposal was to correlate those streams using timestamps,
button identifiers and event direction.

```text
IOHID callback                         CGEventTap
device + usage + value + time          button + down/up + time
             \                          /
              \                        /
               ---- correlation queue -
                         |
                         v
                 physical mouse identity
                         |
                         v
                   bound mapping set
```

Advantages:

- Uses documented/public API families.
- Can theoretically support simultaneous mice.

Risks:

- The streams can arrive in different orders.
- Timestamps may use different clocks or precision.
- Coalescing, latency and rapid clicks can produce ambiguous matches.
- Klik PRO must suppress or pass the `CGEvent` promptly; waiting too long is
  unsafe and can cause the event tap to be disabled.
- More state, timeouts and recovery logic are required.

The correlation method should be retained only as a possible public-API
fallback or research path. It should not be the first production implementation.

## 5. Recommended proposal: direct event sender identity

[OpenLogi](https://github.com/AprilNEA/OpenLogi) demonstrates a more direct
macOS mechanism in its
[macOS hook implementation](https://github.com/AprilNEA/OpenLogi/blob/master/crates/openlogi-hook/src/macos.rs):

1. Obtain the backing `IOHIDEvent` from the intercepted `CGEvent` using
   `CGEventCopyIOHIDEvent`.
2. Read its sender registry ID using `IOHIDEventGetSenderID`.
3. Resolve that registry ID through IORegistry.
4. Walk the service and its parents to find product name, vendor ID, product ID
   and other useful properties.
5. Cache the resolution so the event-tap callback stays fast.

```text
CGEventTap receives button event
              |
              v
      CGEventCopyIOHIDEvent
              |
              v
      IOHIDEventGetSenderID
              |
              v
        IORegistry entry
              |
              v
 VID / PID / serial / product / location
              |
              v
   bound mapping-set lookup
              |
        +-----+------+
        |            |
     matched      no match
        |            |
 device mapping   fallback mapping
        |            |
        +-----+------+
              |
              v
       execute or pass event
```

This removes the race between separate HID and Quartz event streams. OpenLogi
currently demonstrates the identity lookup in its scroll path; Klik PRO would
extend the same sender extraction to button events.

### Why this is the preferred experiment

- The identity belongs to the same event Klik PRO is already deciding whether
  to suppress.
- Simultaneously connected mice can have different mappings.
- The device association becomes functional rather than decorative metadata.
- IORegistry parent lookup may also improve device names missed by the current
  scanner.
- The sender/registry approach is generic macOS HID plumbing, so it can help
  both Logitech and non-Logitech devices such as the HP Wireless Mouse 201.

### Important limitation

`CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID` are undocumented/private
symbols. They have been used by existing mouse utilities, but Apple does not
promise compatibility.

Klik PRO must therefore:

- Resolve the symbols dynamically with `dlsym`; do not make application launch
  depend on static linkage to them.
- Treat either missing symbol or a zero/unresolvable sender ID as normal.
- Never block inside the event-tap callback.
- Cache registry resolutions and invalidate them on device changes.
- Keep an explicit fallback mapping.
- Test every supported macOS release and both Intel/Apple Silicon if supported.
- Review distribution/notarization/App Store implications before release.

## 6. Identity model

The current persisted identity is a useful start:

```text
vendorID + productID + optional serialNumber
```

Recommended runtime identity:

```text
senderRegistryID
vendorID
productID
serialNumber?
locationID?
transport?
productName?
```

Persistence rules:

- Prefer VID/PID/serial when a serial is present.
- For devices without a serial, add a stable location or registry-derived
  discriminator if testing proves it survives reconnects.
- Never use the editable profile name as hardware identity.
- Treat product name as presentation metadata, not identity.
- Cache the last known friendly name so a temporarily disconnected mouse still
  reads “HP Wireless Mouse 201,” not only a hexadecimal code.
- Warn when two identical serial-less receivers cannot be distinguished.

The HP receiver reported no serial in the earlier probe. Therefore two identical
HP receivers may remain ambiguous unless a stable location property is
available.

## 7. Routing rules

Recommended deterministic precedence:

1. Resolve sender identity from the event.
2. Find the one mapping set bound to that identity.
3. If found, use it even when another mapping set is open in Settings.
4. If the sender is known but unassigned, use the configured fallback policy.
5. If the sender cannot be resolved, use the active fallback mapping.
6. If the selected action is `No Action`, pass or suppress according to the
   control's defined native behavior; never inherit another mouse's assignment.

Browsing a mapping set in Settings must not change runtime routing. “Viewed,”
“active fallback” and “matched physical device” are distinct states.

Suggested UI states:

```text
VIEWING          Office
ASSIGNED MOUSE   Logi M650
CONNECTED        Yes
EVENT ROUTING    Device-specific
FALLBACK         Default
```

The UI should show “Scanning for mice…” while enumeration is running and a clear
empty result such as “No compatible external mice found” when it finishes.

## 8. OpenLogi boundary: reference only, no code reuse

OpenLogi is used only as evidence that sender-aware attribution is technically
feasible on macOS. **Do not copy, translate, adapt or derive code from OpenLogi.**
Klik PRO must implement the design independently in Swift using its existing
architecture and macOS platform interfaces.

The independently implemented design may pursue these general behaviors:

- Obtain an event's sender identity.
- Resolve that identity to an IORegistry device.
- Read appropriate device properties.
- Cache resolved identities for event-tap performance.
- Recover safely from event-tap timeout or unavailable functionality.

Do not use:

- OpenLogi source code or translated versions of it.
- Its Rust implementation structure.
- Its full background agent or HID++ stack.
- Its GUI, wording, tests, assets or branding.
- Logitech-only assumptions for generic mouse routing.

Because no OpenLogi code will be incorporated, its software license is not the
basis for Klik PRO's implementation. Keep the repository link only as research
provenance for the feasibility observation.

## 9. Phased implementation plan

### Phase 0 — diagnostic proof, no behavior change

Add an opt-in diagnostic that logs, for each relevant event:

```text
event=middleDown
senderID=0x...
vendorID=0x046D
productID=0xB02A
serial=...
product=Logi M650
```

Test:

- Logi M650 through its actual connection path.
- HP Wireless Mouse 201 through its USB dongle.
- MX Master 3 Mac if available.
- Rapid alternating clicks from two connected mice.
- Disconnect/reconnect and sleep/wake.

Success criterion: each device consistently produces a distinct sender identity,
and button down/up from one click resolve to the same device.

### Phase 1 — improve discovery and naming

- Add IORegistry parent-property fallback when `IOHIDManager` gives an empty or
  generic product name.
- Show an in-progress scanning state.
- Preserve last known product names for disconnected assignments.
- Clearly distinguish “not connected,” “not found” and “unassigned.”

This phase improves the UI but must not claim device-specific routing yet.

### Phase 2 — device-specific button routing

- Add the sender resolver and bounded cache to the input helper.
- Resolve the mapping set for every intercepted button event.
- Route Middle, Back and Forward first.
- Preserve the current global fallback path.
- Ensure down/up pairs cannot change ownership midway through a click.

### Phase 3 — wheel and special controls

- Attribute supported scroll/thumb-wheel events.
- Keep the existing MX Master 3 Gesture sentinel path until sender-aware Gesture
  handling is separately proven.
- Define behavior for devices that expose special controls as keyboard or
  consumer-control events rather than mouse buttons.

### Phase 4 — hardening

- Test event-tap timeout recovery and symbol-unavailable fallback.
- Measure callback latency and cache hit rate.
- Add migration and duplicate-device-binding tests.
- Add diagnostics that contain no personal data beyond explicitly requested HID
  identity fields.
- Verify signed DMG behavior on clean supported macOS installations.

## 10. Acceptance tests

The feature is not complete until all of these pass:

1. With M650 and HP connected, assign different middle-button apps and confirm
   each physical mouse launches only its own assignment.
2. Clicking with an unassigned mouse never borrows the viewed mapping set.
3. Changing the viewed carousel page does not change runtime routing.
4. Renaming “Default” to “Office” does not change the displayed mouse name.
5. Disconnect/reconnect preserves the correct binding.
6. Sleep/wake restores routing without restarting Klik PRO.
7. A missing private symbol leaves mouse input native and the app usable.
8. Rapid alternating clicks do not cross-route down/up events.
9. Two profiles cannot bind the same stable identity silently.
10. A serial-less device displays an explicit ambiguity warning when another
    indistinguishable device is present.

## 11. Decision

Prototype an independently designed direct sender-ID mechanism first. OpenLogi
is feasibility evidence only and must not be used as an implementation source.

If the diagnostic proves stable on the supported macOS versions and all three
test mice, use it for real per-device routing with a global fallback. Keep
arrival-based activation as a public-API compatibility mode. Do not build the
timestamp-correlation architecture unless private sender lookup proves
unusable and simultaneous per-device behavior remains a release requirement.
