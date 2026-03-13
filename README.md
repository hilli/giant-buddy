# Giant Buddy iOS

Giant Buddy is an iPhone and Apple Watch companion for Giant e-bikes with RideControl+.
It connects over BLE using the Giant GEV protocol, shows live bike telemetry, records rides with GPS, and adds navigation, analytics, safety features, and bike-health tooling around the ride itself.

It is the iOS/watchOS evolution of [giant-esp32](https://github.com/hilli/giant-esp32): same protocol family, but with phone-grade maps, HealthKit, background operation, widgets, and much richer ride history.

## Highlights

- Live ride dashboard with speed, cadence, torque, motor power, estimated rider power, battery, range, weather, and a map
- Route library with GPX import, on-map route creation, destination search, POI categories, and favorite places
- Active navigation with remaining distance, route progress, off-route detection, rerouting, voice guidance, and haptics
- Ride recording with GPS + bike telemetry, Apple Watch heart rate, background operation, and detailed post-ride charts
- Bike tab with connection state, bike info, maintenance tracking, battery health, and controls on supported bikes
- CSV/GPX export, Strava upload, analytics, crash detection, Live Activities, widgets, and a watchOS companion

## Feature Overview

### Ride Dashboard and Controls

- Auto-scan and reconnect to paired Giant bikes over BLE
- Real-time speed, cadence, torque, motor power, estimated rider power, battery percentage, remaining range, ride distance, and ride time
- In-ride map with current position, route overlay, and recorded trail
- Recording controls directly from the dashboard
- Bike controls for light, assist changes, and power on supported bikes
- Weather snapshot and Apple Watch heart-rate display
- Compact in-ride layout for landscape use

### Routes, Search, and Navigation

- Import GPX routes into **My Routes**
- Create and edit routes directly on the map
- Search by address or place name
- Browse POI shortcuts for common ride stops
- Save favorite places for quick reuse
- Route previews with distance, elevation, estimated time, and battery-range prediction
- Start navigation from saved routes or destination search results
- Active navigation with remaining distance, completion progress, off-route detection, rerouting, optional voice prompts, and haptic feedback
- Optional setting to end navigation automatically when a ride stops

### Ride Recording, History, and Analytics

- Record GPS and bike telemetry in the background
- Store rides locally with SwiftData
- Browse ride history with summary cards and route maps
- Inspect ride details with interactive charts for speed, motor power, rider power, elevation, and battery
- Scrub ride charts to inspect any recorded point in time
- Save a recorded ride as a reusable route
- Export rides as CSV or GPX
- Upload rides to Strava
- View analytics across week, month, year, or all-time periods

### Bike Info, Maintenance, and Battery Health

- View frame number, odometer, firmware versions, and bike-specific status data
- Inspect battery charge, health, capacity, and charge-cycle information
- Track maintenance items against odometer distance or date
- Review stored battery-health snapshots over time
- Review bike error-log history captured from the protocol

### Safety, Watch, Widgets, and Integrations

- Crash detection with emergency contacts, countdown alert, and test mode
- Optional Apple Fitness workout logging
- watchOS companion app for at-a-glance ride data
- Apple Watch heart-rate sharing during rides
- Home Screen widgets for recent ride information
- Live Activity / Dynamic Island support while recording
- Strava OAuth integration for post-ride upload

## Compatibility

- iOS 17.0+
- Xcode 16+
- Giant e-bike with RideControl+ BLE telemetry
- Tested with Stormguard E+ 2 (2023)

> [!NOTE]
> Bike controls depend on what the bike and display expose over BLE. Telemetry, recording, history, and navigation can still be useful even on bikes where remote assist/light/power commands are not available.

## Build and Run

### Xcode

Open `GiantLogger.xcodeproj` in Xcode, select a simulator or device, and build the `GiantLogger` scheme.

### Taskfile helpers

This repository also includes a `Taskfile.yaml` with common workflows:

- `task build:quiet` — build the iOS app in Debug
- `task simulator` — build and launch in the iOS Simulator
- `task deploy` — install and launch on a connected iPhone
- `task lint` — run SwiftLint (if installed)
- `task format:check` — verify SwiftFormat formatting
- `task setup` — install SwiftLint and SwiftFormat via Homebrew

## Data and Export

- **CSV export** includes ride telemetry plus GPS columns for external analysis
- **GPX export** includes the recorded track with elevation, cadence, speed, and power-related fields
- Recorded rides can be saved back into the app as reusable routes

## Protocol

The bike connection uses the Giant GEV BLE protocol.
For reverse-engineering notes and lower-level protocol details, see [protocol.md](https://github.com/hilli/giant-esp32/blob/main/docs/protocol.md) in the `giant-esp32` repository.

## License

MIT
