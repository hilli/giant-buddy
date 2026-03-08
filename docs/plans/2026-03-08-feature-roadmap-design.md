# GiantLogger Feature Roadmap — Implementation Plan

## Problem Statement

GiantLogger is a mature e-bike telemetry app (~4,250 LoC) with live dashboard, ride recording, GPS tracking, Strava/HealthKit integration, and weather. The next evolution is to make it a **complete ride companion** — not just a logger, but an app that helps plan, navigate, analyze, and maintain your e-bike riding experience.

## Target User

Primary: The developer (commuting + recreational rider on a Giant e-bike). Design for broader Giant e-bike owner audience.

## Proposed Approach

Seven feature directions, organized into four phases. Each phase builds on the previous and delivers standalone value. Phases are ordered by impact, feasibility, and dependency relationships.

---

## Phase 1: Routes, Search & Analytics (Foundation)

The highest-impact, most-requested features. Routes and search make the app a ride companion; analytics leverage existing data.

### 1A. GPX Import, Route Following & My Routes

- **GPX parser** — parse `.gpx` files (tracks + routes) into a `Route` SwiftData model
- **Import sources** — iOS Share Sheet, Files app, URL schemes, in-app file picker
- **Map overlay** — display planned route as a polyline on the dashboard map
- **Breadcrumb following** — show rider position on route, highlight upcoming path
- **Progress indicators** — distance remaining, % complete, elevation profile preview
- **Off-route alert** — detect when rider deviates >100m from route, show visual/haptic alert
- **"My Routes" tab** — dedicated tab showing all saved routes:
  - Imported GPX routes
  - Routes saved from completed rides ("Save as Route" button on RideDetailView)
  - Route cards showing: name, distance, elevation gain, last ridden date
  - Swipe to delete, tap to preview on map or start navigation
- **Ride-to-Route conversion** — convert any completed ride's GPS track into a reusable Route
- **iCloud sync** — routes sync via CloudKit (same as rides)

**New files:** `Route.swift` (model), `GPXParser.swift` (service), `MyRoutesView.swift`, `RouteMapView.swift`, `ActiveNavigationView.swift`  
**Modified files:** `DashboardView.swift` (add route overlay), `ContentView.swift` (replace History tab position or add 5th "My Routes" tab), `RideDetailView.swift` (add "Save as Route" action)

### 1B. POI & Address Search

- **Address search** — search bar using `MKLocalSearch` to find any address or place, get directions
- **Category search tabs** — quick-access buttons for cyclist-relevant POI categories:
  - 🚻 **Public toilets** — search nearby public restrooms
  - 🔧 **Bicycle repair shops** — search nearby bike shops and repair services
  - ⚡ **E-bike charging** — search for charging stations (where available)
  - ☕ **Cafés & rest stops** — search nearby cafés and restaurants
- **Search results on map** — display results as pins on the map with distance from current location
- **Navigate to result** — tap a result to get cycling directions (uses MKDirections), optionally save as route
- **Recents** — remember recent searches for quick re-access
- **Integration with routes** — search results can be added as waypoints to an existing route

**New files:** `SearchView.swift`, `POISearchService.swift`, `SearchResultsMapView.swift`  
**Modified files:** `ContentView.swift` (integrate search into navigation or as search overlay on map views)

### 1C. Ride Analytics & Trends

- **Summary dashboard** — weekly/monthly cards: total distance, ride count, avg speed, elevation, battery consumed
- **Trend charts** — line charts over weeks/months for speed, power, cadence, distance, efficiency
- **Personal records** — fastest, longest, most elevation, best efficiency (km/% battery)
- **Energy efficiency metric** — "km per % battery" adjusted for elevation gain
- **Route comparison** — compare rides on the same route (detect by start/end proximity or manual tagging)

**New files:** `AnalyticsView.swift`, `TrendsViewModel.swift`  
**Modified files:** `ContentView.swift` (add Analytics tab or section), `Ride.swift` (add computed properties for aggregation)

---

## Phase 2: Intelligence (builds on Phase 1 routes)

### 2A. Smart Range Prediction

*Depends on: Phase 1A (routes/my routes)*

- **Consumption model** — calculate Wh/km at each assist level from historical ride data (battery drain + distance + elevation)
- **Route energy estimate** — given a loaded route's elevation profile + current battery %, predict remaining battery at each point
- **"Can I make it?" indicator** — green/yellow/red overlay on route map showing predicted battery level
- **Assist mode advisor** — "Switch to Eco after km 15 to complete this route" recommendations
- **Learning engine** — improve predictions over time by comparing predicted vs. actual battery usage per ride
- **Range display** — show estimated remaining range for each assist mode on dashboard (already partially exists)

**New files:** `RangePredictor.swift` (service), `RangePredictionView.swift`  
**Modified files:** `RouteMapView.swift` (add prediction overlay), `DashboardView.swift` (add advisor alerts)

### 2B. Maintenance Tracker

- **Maintenance model** — `MaintenanceItem` (component name, install date, install odometer, service interval km/days)
- **Built-in components** — chain, brake pads, tires, battery, motor with suggested service intervals
- **Service reminders** — local notifications when distance/time thresholds are reached
- **Battery health timeline** — chart battery health % over time (requires periodic BatteryData snapshots)
- **Error code history** — persist every error code from BLE with timestamp + odometer
- **Service report export** — shareable text/PDF summary of bike health + maintenance history

**New files:** `MaintenanceItem.swift` (model), `BatterySnapshot.swift` (model), `ErrorLog.swift` (model), `MaintenanceView.swift`, `BatteryHealthView.swift`  
**Modified files:** `GiantBikeService.swift` (persist error codes + battery snapshots), `SettingsView.swift` or `ConnectionView.swift` (link to maintenance)

---

## Phase 3: Full Navigation (builds on Phase 1 routes)

### 3A. On-Map Route Creation

*Depends on: Phase 1A*

- **Waypoint editor** — tap map to add waypoints, drag to reorder
- **Cycling directions** — use `MKDirections` with `.cycling` transport type between waypoints
- **Elevation profile** — show elevation chart for created route before riding
- **Route editing** — add/remove/move waypoints, recalculate directions
- **Save & name** — persist created routes to SwiftData/iCloud
- **Reverse route** — one-tap to reverse a saved route for the return trip

**New files:** `RouteEditorView.swift`, `ElevationProfileView.swift`  
**Modified files:** `Route.swift` (add waypoints), `RouteListView.swift` (add "Create" button)

### 3B. Turn-by-Turn Navigation

*Depends on: Phase 3A*

- **Navigation engine** — monitor position against route, calculate upcoming turns
- **Navigation UI** — top banner with direction arrow, distance to next turn, street name
- **Voice announcements** — AVSpeechSynthesizer for turn alerts ("Turn left in 200 meters")
- **Haptic feedback** — vibration patterns for turns (works even with phone in pocket)
- **Re-routing** — detect off-route and recalculate using MKDirections
- **Arrival detection** — auto-stop navigation near destination

**New files:** `NavigationEngine.swift` (service), `NavigationBannerView.swift`  
**Modified files:** `DashboardView.swift` (integrate navigation banner), `ActiveNavigationView.swift` (add turn-by-turn mode)

---

## Phase 4: Connection & Polish

### 4A. Live Sharing & Safety

- **Crash detection** — detect sudden deceleration + no movement for 60s, trigger alert with countdown, send SMS/notification with GPS coordinates to emergency contacts
- **Emergency contacts** — settings page to configure 1-3 emergency contacts
- **Live location sharing** — generate a shareable link showing real-time position on a web map (requires lightweight backend — CloudKit public DB or simple web service)
- **ETA sharing** — for loaded routes, share estimated arrival time that updates live

**New files:** `CrashDetector.swift` (service), `EmergencyContactsView.swift`, `LiveSharingService.swift`  
**Modified files:** `SettingsView.swift` (add emergency contacts + sharing settings)

### 4B. Widgets & Live Activities

- **Live Activity** (highest priority) — during active ride, show speed/distance/battery/time on Dynamic Island + Lock Screen
- **Home Screen widgets** — battery %, last ride summary, today's weather
- **Lock Screen widgets** — battery %, quick stats
- **Apple Watch companion** (stretch goal) — live metrics on wrist, start/stop recording, haptic navigation alerts

**New targets:** Widget Extension, (optional) WatchKit Extension  
**New files:** `GiantLoggerWidget/` target with widget views, `ActivityAttributes.swift` for Live Activities  
**Modified files:** `RideRecorder.swift` (start/update/end Live Activity), shared App Group for widget data

---

## Architecture Notes

- **Data layer:** All new models use SwiftData with CloudKit sync (consistent with existing Ride/RideSample)
- **Navigation state:** New `NavigationState` observable object to coordinate route following, turn-by-turn, and range prediction
- **Tab structure:** Current 4 tabs (Ride, History, Bike, Settings). Plan: reorganize to 5 tabs — **Ride** (dashboard), **My Routes** (saved routes + GPX import), **History** (past rides + analytics), **Bike** (diagnostics + maintenance), **Settings**. Search is accessible as a sheet/overlay from the Ride and My Routes tabs.
- **No backend needed** until Phase 4A (live sharing). Everything else is on-device.

## Key Dependencies

```
Phase 1A (Routes/My Routes) ──► Phase 2A (Range Prediction)
Phase 1A (Routes/My Routes) ──► Phase 3A (Route Creation)
Phase 1B (POI Search) ────────► integrates with Routes (add POI as waypoint)
Phase 3A (Creation) ──────────► Phase 3B (Turn-by-Turn)
Phase 1C (Analytics)   [independent]
Phase 2B (Maintenance) [independent]
Phase 4A (Safety)      [independent]
Phase 4B (Widgets)     [independent, but Live Activity benefits from navigation]
```

## Risks & Considerations

- **MKDirections cycling** — Apple's cycling directions are not available in all countries. May need fallback to walking directions or third-party routing API (e.g., OpenRouteService)
- **Turn-by-turn accuracy** — GPS accuracy on phones varies; need to handle tunnel/bridge/urban canyon scenarios gracefully
- **Battery impact** — continuous GPS + BLE + navigation could drain phone battery; need to monitor and optimize
- **Live sharing backend** — only feature requiring infrastructure beyond the device; could defer or use CloudKit public database to avoid running a server
- **App Store review** — crash detection features may need careful wording to avoid implying medical-grade safety
