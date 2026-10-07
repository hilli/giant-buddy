# Copilot instructions for Giant Buddy iOS

## Build, lint, and run commands

- Open `GiantLogger.xcodeproj` in Xcode 16+ and build the `GiantLogger` scheme for iOS 17+.
- `task build:quiet` builds the iOS app in Debug with quiet `xcodebuild` output.
- `task build -- <extra xcodebuild args>` builds Debug for `generic/platform=iOS`; pass extra args through `CLI_ARGS`.
- `task build:release` builds Release for `generic/platform=iOS`.
- `task simulator` builds and launches the app in the iOS Simulator, defaulting to `platform=iOS Simulator,name=iPhone 17 Pro Max`; override with `SIM_DEST='platform=iOS Simulator,name=...'`.
- `task deploy`, `task deploy:ota`, and `task deploy:release` build, install, and launch on a connected or paired iPhone.
- `task testflight` archives Release and uploads it to App Store Connect via `ExportOptions-AppStore.plist`; Xcode bumps the build number on upload, so don't edit `CURRENT_PROJECT_VERSION` for TestFlight builds.
- `task lint` runs `swiftlint lint --strict`; `task lint:fix` runs SwiftLint autocorrection.
- `task format:check` runs `swiftformat GiantLogger/ --lint`; `task format` formats `GiantLogger/`.
- `task setup` installs SwiftLint and SwiftFormat with Homebrew.

## Architecture overview

- The app target is `GiantLogger`; companion targets are the iOS widget extension, watchOS app, and watch widget extension. The Xcode project uses file-system synchronized root groups, so new Swift files placed under a target folder are generally picked up by that target.
- `GiantLoggerApp` is the composition root. It creates one static `Services` bundle, stores services as `@StateObject`s, wires dependencies before BLE callbacks can arrive, injects services as environment objects, owns the shared SwiftData `ModelContainer`, handles scene-phase reconnect behavior, and routes Strava/GPX URL callbacks.
- BLE is intentionally split into two layers: `BikeManager` owns CoreBluetooth scanning, connection, restoration, service/characteristic discovery, and raw writes for the GEV service; `GiantBikeService` owns the encrypted GEV protocol handshake, command scheduling, packet parsing, telemetry state, cached bike info, and polling.
- Ride recording flows through `RideRecorder`: it subscribes to `GiantBikeService.isGevConnected`, auto-starts/stops based on `autoRecord`, samples every 2 seconds from bike telemetry plus `LocationManager` GPS and Watch heart rate, writes SwiftData `Ride`/`RideSample`, updates Live Activities/widgets/Watch, optionally logs HealthKit workouts, and uploads to Strava when enabled.
- Routes use SwiftData `Route` and `RouteWaypoint`. `GPXParser` imports GPX files into routes; `NavigationEngine` calculates MapKit directions between key route waypoints, falls back from cycling to walking, detects off-route/reroute/arrival state, and sends navigation updates to Apple Watch.
- Cross-target state uses the `group.dk.hilli.GiantLogger` App Group. `SharedBikeData` stores widget/complication values in app-group `UserDefaults`; keep mirrored shared-data files in extension targets consistent when adding keys. `WatchConnectivityManager` on iPhone and `WatchSessionManager` on Watch exchange telemetry, recording commands, navigation state, and live heart rate.

## Codebase conventions

- Most service classes that publish UI state are `@MainActor ObservableObject`s with `@Published` properties. Framework delegate callbacks are commonly `nonisolated` and hop back to the main actor with `Task { @MainActor in ... }`.
- Preserve the BLE/GEV layering: do not put CoreBluetooth lifecycle logic in `GiantBikeService`, and do not parse/decrypt GEV protocol payloads in `BikeManager`. Build and decode GEV packets through `GiantProtocol`.
- Be careful with BLE timing. Initial data fetches and polling intentionally serialize commands with short sleeps so the bike BLE stack is not overwhelmed; keep command batching/throttling internal to the services.
- SwiftData models live under `GiantLogger/Models` and use optional relationship arrays plus computed sorted accessors (`Ride.samples`, `Route.sortedWaypoints`). Update `GiantLoggerApp.sharedModelContainer` whenever adding a persisted model.
- Persistent settings are mostly string-keyed `UserDefaults`/`@AppStorage` values (`autoRecord`, `logWorkouts`, `savedDeviceID`, `autoConnectEnabled`, `debugLogEnabled`, etc.). Reuse existing keys and defaults rather than introducing parallel settings.
- Units in persisted ride/route data are kilometers, km/h, meters, seconds, watts, RPM, newton-meters, amps, and battery percent. Keep export/import and UI formatting consistent with those units.
- Use `Logger(subsystem: "dk.hilli.GiantLogger", category: "...")` for system logging and `DebugLogger.shared.log(...)` for on-device BLE/GEV diagnostics that users can export.
- Strava credentials are local-only: copy `GiantLogger/StravaSecrets.swift.example` to `GiantLogger/StravaSecrets.swift`; the real file is git-ignored.
- Inline SwiftLint suppressions are used for targeted exceptions, e.g. `// swiftlint:disable:next cyclomatic_complexity`; prefer a local suppression over broad rule changes.
