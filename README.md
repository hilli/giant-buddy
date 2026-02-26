# Giant Logger iOS

iOS companion app for Giant e-bikes with RideControl+. Communicates with the bike over BLE using the Giant GEV protocol (AES-128-ECB encrypted), logs ride telemetry with GPS tracking, and exports rides as CSV/GPX.

Ported from [giant-esp32](https://github.com/hilli/giant-esp32) — same protocol, better hardware (GPS, waterproof, big screen, unlimited storage).

## Features

- **BLE Connection** — Auto-scan and connect to Giant e-bikes via the GEV GATT service
- **Live Dashboard** — Real-time speed, power, cadence, torque, battery, distance, time, range
- **GPS Tracking** — Record GPS track during rides (the ESP32 couldn't do this!)
- **Ride Logger** — Record telemetry + GPS every 2 seconds, stored locally with SwiftData
- **Ride History** — Browse past rides with summary stats, map tracks, and charts
- **Bike Controls** — Toggle light, adjust assist level, power on/off
- **Export** — CSV (compatible with ESP32 format + GPS columns) and GPX for Strava/Komoot
- **Background Mode** — BLE + GPS stay active when phone is in pocket
- **Bike Info** — Frame number, odometer, firmware versions, battery health

## Requirements

- iOS 17.0+
- Xcode 16+
- Giant e-bike with RideControl+ (tested with Stormguard E+ 2, 2023)

## Building

Open `GiantLogger.xcodeproj` in Xcode, select your device, and build.

## Protocol

See [protocol.md](https://github.com/hilli/giant-esp32/blob/main/docs/protocol.md) in the ESP32 repo for full protocol documentation.

## Screenshots

### Dashboard
```
┌─────────────────────────────┐
│  ● Connected to GIANT-RC    │
│                             │
│          24.5               │
│          km/h               │
│                             │
│  ⚡ 250W   🔄 85rpm  ⚙ 45Nm│
│                             │
│  🔋 72%    📏 15.3km        │
│            ⏱ 0:32:15       │
│            ⛽ 25km range     │
│                             │
│  ┌─────────────────────┐    │
│  │     ~ map ~         │    │
│  └─────────────────────┘    │
│                             │
│  [    ⏺ Start Recording   ] │
│                             │
│  💡Light  −Assist  +Assist  │
│                             │
│  🚲Ride  📋History  📡  ⚙  │
└─────────────────────────────┘
```

### Ride Detail
```
┌─────────────────────────────┐
│  ← Feb 26, 2026 10:30 AM  ↗│
│                             │
│  ┌─────────────────────┐    │
│  │  🟢start             │    │
│  │    ╲                 │    │
│  │     ╲___/‾‾╲        │    │
│  │              ╲ 🔴end │    │
│  └─────────────────────┘    │
│                             │
│  📏 32.4 km   ⏱ 1:45:20   │
│  🏎 18.5 km/h  🏁 42.3 km/h│
│  ⚡ 185 W     ⚡ 520 W     │
│  🔄 72 rpm    🔋 95%→41%   │
│                             │
│  Speed ─────────────────    │
│  ╱╲  ╱╲╱╲   ╱╲             │
│ ╱  ╲╱    ╲_╱  ╲___         │
│                             │
│  Power ─────────────────    │
│  █▄█▄██▄▄█████▄█▄▄▄        │
│                             │
│  Battery ───────────────    │
│  ‾‾‾‾‾‾‾‾‾╲                │
│             ‾‾‾‾‾╲____     │
└─────────────────────────────┘
```

## License

MIT
