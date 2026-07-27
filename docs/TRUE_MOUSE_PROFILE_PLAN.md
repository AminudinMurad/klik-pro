# True mouse profile implementation plan

Status: design and investigation plan. v1.5.0 does **not** implement this
feature. It stores mapping presets and allows only one preset to be active.

## Goal

Make a mouse profile represent both a saved mapping and the physical HID mouse
that produced the event:

```text
Logi M650 middle button  -> Work mouse mapping  -> Open Claude
MX Master 3 middle       -> Personal mapping   -> Browser back
Unknown/unbound mouse    -> safe fallback       -> pass through/no action
```

The required property is sender-aware routing, not merely a device picker:

> For every supported button or wheel event, Klik PRO must determine the source
> mouse, select that device's mapping, and then execute or suppress the event.

## Current state and non-goals

Current v1.5.0 already has useful persistence primitives:

- `MouseProfile` mapping records and stable profile IDs.
- `MouseDeviceIdentity` values containing vendor/product data and optional serial.
- IOHID device enumeration and cached display names.
- A single active mapping consumed by the helper.
- A `CGEventTap` that sees the events Klik PRO may suppress.

What it does **not** have is a reliable source identity attached to each
intercepted event. Do not claim device isolation because a scan succeeded.

Non-goals for the first true-routing release:

- Simultaneous multi-active profiles with different rules for the same physical
  button on one device.
- Vendor-specific driver integration.
- A broad device-management UI before the routing proof works.
- Changing shortcut recording, App Profiles, or browser behavior at the same time.

## Proposed data model

Keep the mapping and hardware identity separate so a user can rename a mapping
without renaming a device:

```swift
struct MouseProfile {
    let id: UUID
    var name: String                 // “Work”, “Travel”, etc.
    var deviceBinding: MouseDeviceBinding?
    var mapping: MouseMapping        // existing button/wheel settings
}

struct MouseDeviceBinding {
    var identity: MouseDeviceIdentity
    var displayName: String          // cached, user-facing only
    var lastSeen: Date?
}
```

The persisted identity should be layered, from strongest to weakest:

1. IOHID registry ID while the device is connected (runtime only; never the
   sole persisted key).
2. Serial number plus vendor/product IDs when available.
3. Vendor/product plus transport/location information when no serial exists.
4. An explicit unresolved state; never silently bind a different device merely
   because it has the same VID/PID.

Persist a binding state such as `resolved`, `disconnected`, or `ambiguous` and
show that state in the UI. A cached product name is not proof of identity.

## Recommended technical approach

### Phase 0 — instrument before changing behavior

Add a debug-only event trace that records, without user data:

- CGEvent type/button/scroll direction and monotonic timestamp.
- Whether `CGEventCopyIOHIDEvent` returns an `IOHIDEvent`.
- `IOHIDEventGetSenderID` result.
- Resolved IORegistry service ID, VID, PID, serial, product, transport, and
  location when available.
- Lookup duration and whether the event was passed through or suppressed.

Never log keystroke contents or app data. Gate the trace behind an explicit
development flag and keep it out of release builds.

### Phase 1 — prove sender extraction in a standalone probe

Build a small test tool under `diagnostics/` that:

1. Installs a temporary `CGEventTap` for mouse buttons and supported scrolls.
2. Calls `CGEventCopyIOHIDEvent` for each event.
3. Reads the sender registry ID using `IOHIDEventGetSenderID`.
4. Resolves the sender through IOKit/IORegistry.
5. Prints a stable identity summary and timing statistics.

Test cases:

- MX Master 3 only.
- Logi M650 only.
- Both connected, alternating clicks rapidly.
- Bluetooth reconnect.
- USB receiver disconnect/reconnect.
- Sleep/wake.
- A normal built-in trackpad or keyboard event, which must never be treated as
  a supported external mouse.

Success means at least 100 alternating events across two mice resolve to the
correct source with no ambiguous or missing sender IDs. If sender extraction is
not available for a class of event, document that class before proceeding.

### Phase 2 — add a runtime identity resolver

Implement a small, thread-safe `MouseEventSourceResolver` in the input target:

```text
CGEventTap callback
        |
        v
copy IOHIDEvent -> sender registry ID
        |
        v
bounded identity cache (registry ID -> MouseDeviceIdentity)
        |
        v
profile binding lookup
```

Requirements:

- The callback must remain bounded and fast. Resolve IORegistry properties on a
  background queue and cache them; do not perform unbounded tree walks for every
  click.
- On a cache miss, use a short timeout and a safe fallback. Never block the
  event tap waiting for a device scan.
- Invalidate registry-ID cache entries on device termination and sleep/wake.
- Treat an unknown or ambiguous source as unbound. The fallback must not apply a
  random profile.
- Keep button down/up decisions consistent: the mapping selected on button-down
  must be retained for the matching button-up if the device disappears or the
  active config changes mid-click.

### Phase 3 — bind profiles and preserve migration safety

Add an optional binding field to the existing profile model and bump the config
schema only after migration tests exist.

Migration rules:

- Existing v1.5.0 configs remain valid and become an unbound/default profile.
- Existing profile IDs, names, mappings, colours, assignments, and active ID
  remain unchanged.
- Binding is never inferred from profile order or the currently connected mouse.
- A device can be bound to at most one profile unless the UI explicitly offers
  a shared binding rule.
- Deleting a profile removes only that profile's binding; it must not reassign
  the device to another profile.
- Reset Mapping clears mapping values but should preserve the profile's name and
  binding unless the UI explicitly offers “Reset binding” separately.

### Phase 4 — replace the misleading UI with real binding UI

Only after the resolver passes the two-device probe:

1. Add **Bind physical mouse…** to a profile's gear menu.
2. Show the current resolved device name, connection state, and a stable short
   identity summary.
3. Offer **Unbind mouse** separately from Save and Activate.
4. Make scanning a discovery aid, not the routing mechanism.
5. Keep profile activation and device binding as distinct operations:

```text
Save mapping       -> persists mapping values
Bind physical mouse -> persists hardware identity
Activate profile   -> selects the fallback/live profile according to policy
```

Recommended first policy: one bound profile per device, with one unbound
fallback profile. If multiple bound mice are connected, both route concurrently;
the fallback applies only to an unresolved/unbound source.

## Safety and fallback policy

- Never suppress an event when source identity is unknown and the configured
  fallback is not explicitly enabled.
- Never route a device to a profile solely from matching VID/PID when multiple
  identical devices are present.
- If a device becomes ambiguous, mark it unresolved and pass events through.
- If the event tap loses accessibility permission or is disabled, restore normal
  event delivery and report the permission state.
- Do not make the settings UI imply that a connected-device list guarantees
  hardware isolation.

## Test plan and acceptance criteria

### Unit and model tests

- Identity equality and matching precedence.
- Serial-present, serial-absent, duplicate VID/PID, and ambiguous cases.
- Schema migration from the v1.5.0 config shape.
- Save, bind, activate, rename, duplicate, reset, delete, and unbind semantics.
- Unknown-source fallback and button down/up state retention.

### Hardware/manual matrix

| Scenario | Expected result |
|---|---|
| One bound mouse | Its profile handles every supported event. |
| Two different bound mice | Each mouse uses only its own profile concurrently. |
| One bound, one unbound | Bound mouse routes; unbound mouse follows explicit fallback/pass-through. |
| Two identical VID/PID without serial | No automatic cross-binding; ambiguous device passes through. |
| Mouse reconnects | Binding resolves again without changing the mapping. |
| Sleep/wake | Cache rebuilds; no stale registry ID routes to the wrong device. |
| Profile renamed | Device binding and routing remain unchanged. |
| Profile deleted | Its device becomes unbound; another profile is never silently selected. |
| Input Monitoring revoked | Events are not suppressed; UI explains recovery. |

### Release gate

Do not expose or advertise true mouse profiles until:

- The sender probe passes with two simultaneous mice.
- Resolver, migration, UI, and event-down/up tests pass.
- The full `tools/check.sh` suite passes.
- A manual test records evidence for both supported test mice and reconnects.
- The release notes clearly distinguish hardware-bound profiles from mapping
  presets.

## Suggested implementation order

1. Instrumentation and standalone sender probe.
2. Resolver cache and identity normalization.
3. Two-device routing behind a development flag.
4. Persistence migration and model tests.
5. Binding UI and explicit fallback policy.
6. Hardware regression matrix and performance profiling.
7. Remove the development flag, update README/handoff, and release only after
   the acceptance criteria are met.
