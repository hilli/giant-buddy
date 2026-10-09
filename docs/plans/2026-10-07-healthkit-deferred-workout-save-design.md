# Deferred HealthKit workout save

## Problem

Rides recorded in "pocket mode" (auto-start/auto-stop on GEV connect/disconnect,
added 2026-03-18) show up in Apple Fitness with 0 kcal, 0.0 km/h average speed
and no distance, or not at all.

The debug log shows why. Auto-stop happens while the phone is locked, and the
Health database is protected data that is unavailable while locked. HealthKit
writes then fail with a misleading `Authorization is not determined` (error 5),
and `finishWorkout` often returns nil. Of 107 workouts started, about 22 were
saved; most of those were saved without their distance/energy samples because
`stopWorkout` finished the workout even when adding samples failed.

Rides from 5–17 March 2026 were stopped in the foreground (background recording
did not work yet) and saved with calories and speed.

The missing app icon in Fitness is unrelated (March workouts lack it too) and is
out of scope; it is being checked with a TestFlight build.

## Decisions

- Build the whole workout after the fact from the persisted `Ride`, whenever
  protected data is available (option A). Rejected: retrying the live builder in
  memory (lost if iOS kills the app) and only notifying the user (fragile).
- No backfill of past rides. The app cannot read Health to detect existing
  workouts, so backfilling would create duplicates.
- Follow-up: since iOS 26 an iPhone app with an active `HKWorkoutSession` can
  write Health data while locked (after a one-time prompt; WWDC25 "Track
  workouts with HealthKit on iOS and iPadOS"). Unverified for pocket mode
  (starting a session from a background BLE wake while locked) and alongside
  the Watch's own workout session. To be tested separately; the deferred save
  stays as the fallback.

## Design

### Data model

`Ride.healthKitStatus: String = "none"` with values `none | pending | saved`.
The default keeps CloudKit/SwiftData lightweight migration working and means
existing rides are never touched.

### WorkoutManager

The live builder is removed (`startWorkout`, `discardWorkout`,
`addRouteLocation`, `stopWorkout`, `ensureAuthorized`, `injectSampleWorkout`).
A single `save(_ ride: Ride) async throws`:

1. `HKWorkoutBuilder` (cycling, outdoor, `device: .local()`),
   `beginCollection(ride.startDate)`.
2. Metadata: ride name as `HKMetadataKeyWorkoutBrandName` (Fitness title),
   `HKMetadataKeySyncIdentifier = ride.id`, `HKMetadataKeySyncVersion = 1`.
   A repeated save with the same identifier and version keeps the existing
   workout, so retries cannot duplicate.
3. Samples: distance (m) from `totalDistance`; energy from average rider power
   (torque × cadence × 2π/60), falling back to motor power, ÷ 0.25 efficiency;
   heart rate from `RideSample.heartRate`.
4. `endCollection(ride.endDate)` → `finishWorkout`.
5. Route from stored GPS samples (`CLLocation` with timestamp, accuracy,
   altitude, speed, course) → `finishRoute`.

### RideRecorder

- Recording start does no HealthKit work; per-sample route inserts are removed.
- After the ride name resolves in `finalizeRide`, a kept ride is marked
  `pending`, saved, and `savePendingWorkouts()` runs.
- `savePendingWorkouts()` fetches `pending` rides and saves them one at a time
  under a background task, marking each `saved`. Guards: `logWorkouts`,
  `UIApplication.shared.isProtectedDataAvailable`, and a re-entrancy flag.
- Triggers: end of `finalizeRide`,
  `protectedDataDidBecomeAvailableNotification`, and scene becoming active.
- iOS does not wake a suspended app on unlock, so when the phone is locked at
  stop the "Ride Recording Stopped" notification adds "Open Giant Buddy to save
  it to Apple Health." Tapping it opens the app, which saves the workout.

### Error handling

- Failure before `finishWorkout` (begin, add samples, end collection): do not
  finish; the ride stays `pending` and is retried. No partial workouts.
- `finishWorkout` error or nil: ride stays `pending`; the sync identifier makes
  a retry after an unrecorded success a no-op.
- Route failure after the workout saved: logged; the ride is still `saved`.
- No retry cap; a failing ride retries on each app open and the debug log shows
  why.

## Verification

No unit test target exists. `task lint`, `task format:check`, device build and
install, then on device:

1. Ride with the phone locked until auto-stop. Debug log: ride marked pending,
   save skipped (protected data unavailable). Unlock, open the app: "Workout
   saved". Fitness shows calories, distance, average speed and route.
2. Ride stopped from the app while unlocked: saved immediately.
