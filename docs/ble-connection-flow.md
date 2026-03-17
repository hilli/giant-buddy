# BLE Connection Flow

This document describes how Giant Buddy connects to a Giant e-bike over Bluetooth Low Energy, how it maintains and restores connections, and the possibilities for background wake-up.

## Architecture Overview

Two services handle the BLE lifecycle:

| Service | Role |
|---------|------|
| **BikeManager** | Core BLE central — scanning, connecting, service/characteristic discovery, raw read/write |
| **GiantBikeService** | GEV protocol layer — encrypts/decrypts packets, manages handshake, parses telemetry |

`BikeManager` is created as a `@StateObject` in `GiantLoggerApp` and injected as an `@EnvironmentObject` throughout the view hierarchy. `GiantBikeService` observes `BikeManager.connectionState` and reacts to `.connected` / `.disconnected` transitions.

## Connection Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        App Launch                               │
│  BikeManager.init()                                             │
│   ├─ Creates CBCentralManager with restoration key              │
│   └─ Loads saved device UUID from UserDefaults                  │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│              centralManagerDidUpdateState(.poweredOn)            │
│   └─ Calls attemptAutoReconnect()                               │
└───────────────────────┬─────────────────────────────────────────┘
                        │
          ┌─────────────┴──────────────┐
          ▼                            ▼
   Has saved device?            No saved device
          │                      (wait for manual scan)
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   attemptAutoReconnect()                         │
│  1. retrieveConnectedPeripherals → already connected? attach    │
│  2. retrievePeripherals(withIdentifiers:) → pending connect     │
│  3. Start active scan in parallel                               │
│  4. 15s timeout (foreground only)                               │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│              didDiscover / didConnect                            │
│   └─ Moves to service discovery                                 │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
             (see "BLE Handshake" below)
```

### Triggers for attemptAutoReconnect()

| Trigger | Location |
|---------|----------|
| BT radio powers on | `centralManagerDidUpdateState(.poweredOn)` |
| App returns to foreground | `onChange(of: scenePhase) { .active → attemptAutoReconnect() }` |

## Manual Scan Flow

```
User taps "Scan for Bikes" on Bike tab
        │
        ▼
BikeManager.startScan()
  ├─ connectionState = .scanning
  ├─ scanForPeripherals(withServices: [GEV service UUID])
  └─ 15s timeout in foreground
        │
        ▼
centralManager(_:didDiscover:advertisementData:rssi:)
  ├─ Appends to discoveredDevices[]
  └─ If peripheral.identifier matches saved UUID → auto-connect
        │
        ▼
Discovered devices appear in Bike tab list
User taps a device
        │
        ▼
BikeManager.connect(to: peripheral)
  ├─ connectionState = .connecting
  ├─ Stops scan
  └─ centralManager.connect(peripheral)
```

## BLE Handshake

Once CoreBluetooth reports `didConnect`, the handshake proceeds through three phases:

### Phase 1: Service & Characteristic Discovery

```
centralManager(_:didConnect:)
  ├─ connectionState = .discoveringServices
  ├─ Saves peripheral UUID to UserDefaults (for future auto-reconnect)
  └─ peripheral.discoverServices([serviceUUID])
        │
        ▼
peripheral(_:didDiscoverServices:)
  └─ peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
        │
        ▼
peripheral(_:didDiscoverCharacteristicsFor:)
  ├─ Stores writeCharacteristic
  ├─ Stores notifyCharacteristic
  └─ peripheral.setNotifyValue(true, for: notifyChar)
        │
        ▼
peripheral(_:didUpdateNotificationStateFor:)
  └─ connectionState = .connected ← BLE link is ready
```

**BLE UUIDs:**

| UUID | Role |
|------|------|
| `4D500001-4745-5630-3031-E50E24DCCA9E` | GEV Service |
| `4D500002-4745-5630-3031-E50E24DCCA9E` | Write Characteristic |
| `4D500003-4745-5630-3031-E50E24DCCA9E` | Notify Characteristic |

### Phase 2: GEV Protocol Handshake

`GiantBikeService` observes `BikeManager.connectionState` and reacts when it becomes `.connected`:

```
GiantBikeService.onConnected()
  ├─ Send connectGEV command (0x02) — AES-encrypted, key index 0
  ├─ Wait up to 5s for ACK (plaintext[2] == 0x01)
  │     └─ If timeout → log error, abort
  └─ On ACK: isGevConnected = true
```

**GEV Packet Format** (20 bytes):

```
[0xFB][0x21][16 bytes AES-ECB encrypted payload][keyIndex][XOR CRC]
```

- 16 AES keys are hardcoded (from decompiled Giant RideControl+ APK)
- `connectGEV` uses key index 0
- No explicit key exchange — authentication is implicit (bike accepts if decryption succeeds)

### Phase 3: Initial Data Fetch

After the GEV handshake ACK:

```
1. requestFactoryData()          — frame number, speed limit, wheel circumference
2. requestDiagnosticSyncDrive()  — live telemetry: speed, torque, cadence, current
3. requestDiagnosticEnergyPak()  — battery diagnostics
4. requestBattery()              — battery level
5. fetchAllBikeData()            — full bike info (motor, RC, errors, range, ODO, etc.)
6. startPolling()                — begin periodic telemetry polling
```

Each request is sent with 500ms delays between them to avoid overwhelming the bike's BLE stack.

## Saved Device Persistence

| UserDefaults Key | Value | Purpose |
|-----------------|-------|---------|
| `savedDeviceID` | Peripheral UUID string | Reconnect to the same bike |
| `savedDeviceName` | Peripheral name | Display before connection |
| `autoConnectEnabled` | Bool | Enable auto-reconnect on launch |
| `cachedBikeInfo` | JSON-encoded BikeInfo | Show bike data offline |
| `cachedFactoryData` | JSON-encoded FactoryData | Show factory data offline |

The device UUID is saved in `centralManager(_:didConnect:)` after a successful connection. Cached bike data is updated after each successful fetch.

## Disconnection & Reconnection

```
centralManager(_:didDisconnectPeripheral:error:)
  ├─ cleanup() → state = .disconnected
  │
  ├─ If error != nil (unexpected disconnect):
  │     └─ Wait 2s → attemptAutoReconnect()
  │
  └─ If error == nil (user-initiated disconnect):
        └─ Stay disconnected
```

### Dashboard Pull-Down Reconnect

The Dashboard view has a `.refreshable` modifier that:
1. If already connected → refreshes telemetry via `fetchAllBikeData()`
2. If not connected → resets any stale `.connecting` state, starts scan, auto-connects to first discovered Giant bike within 10s

## Connection States

```
.disconnected ──► .scanning ──► .connecting ──► .discoveringServices ──► .connected
       ▲                                                                      │
       └──────────────────────── (disconnect) ◄───────────────────────────────┘
```

| State | Meaning |
|-------|---------|
| `.disconnected` | No active connection or scan |
| `.scanning` | Actively scanning for peripherals |
| `.connecting` | Connection request sent to CoreBluetooth |
| `.discoveringServices` | Connected, discovering GEV service & characteristics |
| `.connected` | BLE link fully established, notifications enabled |

---

## Background BLE & Auto-Launch

### What's Already in Place

The app already has the core infrastructure for background BLE:

| Capability | Status | Location |
|-----------|--------|----------|
| `bluetooth-central` background mode | ✅ Enabled | `Info.plist` → `UIBackgroundModes` |
| `CBCentralManagerOptionRestoreIdentifierKey` | ✅ Set | `BikeManager.init()` — key: `"dk.hilli.GiantLogger.central"` |
| `willRestoreState` delegate | ✅ Implemented | `BikeManager` — restores peripheral, re-discovers services |
| Unexpected disconnect → auto-reconnect | ✅ Works | 2s delay then `attemptAutoReconnect()` |

### How Background Wake-Up Works on iOS

iOS Core Bluetooth supports a powerful mechanism for background BLE:

1. **Pending `connect()` never times out.** When you call `centralManager.connect(peripheral)`, iOS keeps this request alive indefinitely — even across app suspension and system-initiated termination.

2. **State restoration re-launches the app.** If the system terminates the app (e.g. for memory pressure) while a pending `connect()` is outstanding, iOS will:
   - Continue monitoring for the peripheral
   - Re-launch the app in the background when the peripheral appears
   - Call `willRestoreState` to hand back the restored central manager
   - Deliver `didConnect` so the app can establish the GEV session

3. **Background scanning** is also possible but throttled — scan intervals increase and duplicate filtering is forced.

### Current Behavior by Scenario

| Scenario | What Happens | Auto-Reconnect? |
|----------|-------------|-----------------|
| App in foreground, bike nearby | Normal connection flow | ✅ Yes |
| App backgrounded, connection active | Connection stays alive, notifications continue | ✅ Yes |
| App backgrounded, connection drops | `didDisconnect` fires → 2s delay → `attemptAutoReconnect()` → pending `connect()` | ✅ Yes |
| App terminated by system, pending `connect()` outstanding | iOS continues monitoring → re-launches app when bike appears → `willRestoreState` | ✅ Yes |
| App force-quit by user | iOS does NOT restore state (by design) | ❌ No |
| App never launched after phone restart | No pending connect exists | ❌ No |

### The Missing Piece: Ensuring a Pending Connect Survives

The current gap: when the app goes to background **without** an active connection (bike is off or out of range), there is no pending `connect()` for the saved peripheral. This means iOS has nothing to monitor and won't re-launch the app.

**Proposed improvement:**

When the app moves to the background (`.inactive` or `.background` scene phase), if the bike is not connected but a saved device exists, issue a pending `connect()`:

```swift
// In GiantLoggerApp.swift, onChange(of: scenePhase):
if newPhase == .background || newPhase == .inactive {
    if bikeManager.connectionState != .connected,
       let savedID = bikeManager.autoConnectIdentifier {
        let peripherals = bikeManager.centralManager
            .retrievePeripherals(withIdentifiers: [savedID])
        if let peripheral = peripherals.first {
            bikeManager.centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true
            ])
        }
    }
}
```

This ensures iOS always has a pending connect request for the saved bike, enabling background wake-up even after the app is terminated by the system.

### Limitations (iOS Constraints)

| Limitation | Reason |
|-----------|--------|
| **Force-quit blocks restoration** | Apple design decision — users who force-quit an app have signaled they don't want it running |
| **Phone restart requires manual launch** | No pending connect exists until the app runs at least once |
| **Background processing limited to ~10s** | iOS gives background-woken apps about 10 seconds to complete their task |
| **No continuous background scanning** | Background scans are throttled (slower intervals, no duplicates) |
| **No guaranteed wake-up timing** | iOS may coalesce events or delay wake-up for power optimization |

### What "Background Data Collection" Could Look Like

With the pending connect improvement, the flow would be:

```
1. User rides bike → app connects, records ride
2. User parks bike, walks away → connection drops
3. App issues pending connect() for saved bike → goes to background
4. System terminates app (memory pressure) — pending connect preserved
5. Next day: user approaches bike
6. iOS detects bike's BLE advertisement
7. iOS re-launches app in background
8. willRestoreState → didConnect → GEV handshake
9. App starts collecting telemetry in background (~10s window)
10. If ride recording is "auto-start" enabled, begin recording
```

The ~10s background window is enough to:
- Establish GEV connection
- Read battery level, ODO, and basic diagnostics
- Start a `BGProcessingTask` or `BGAppRefreshTask` for longer work
- Post a local notification ("Giant Buddy connected to your bike")

For continuous background ride recording, the app would need:
- **Background location updates** (already has `location` in `UIBackgroundModes`)
- Active HKWorkoutSession on the watch (already implemented)
- These keep the app alive for the duration of the ride

### Summary

**Can the app launch automatically when the phone sees the bike?**

**Yes — with one small code change.** The infrastructure is already in place (`bluetooth-central` mode, state restoration, `willRestoreState`). The missing piece is ensuring a pending `connect()` is always outstanding for the saved bike when the app goes to background. iOS will then monitor for the bike and re-launch the app when it appears — no user interaction required.

The only cases where this won't work:
- User force-quits the app (iOS policy, can't work around)
- Phone was restarted and app hasn't been opened yet
