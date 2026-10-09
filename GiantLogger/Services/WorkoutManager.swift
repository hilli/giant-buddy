import Foundation
import HealthKit
import CoreLocation

enum WorkoutSaveError: LocalizedError {
    case healthDataUnavailable
    case finishReturnedNil

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable: "HealthKit is not available on this device"
        case .finishReturnedNil: "finishWorkout returned no workout"
        }
    }
}

/// Saves recorded rides to HealthKit as outdoor cycling workouts.
///
/// Workouts are built after the ride ends from the persisted `Ride`, because
/// HealthKit rejects writes while the phone is locked (pocket-mode auto-stop).
@MainActor
class WorkoutManager: ObservableObject {

    @Published var isAuthorized = false

    private let healthStore = HKHealthStore()
    private let debugLog = DebugLogger.shared

    /// Types we need to write to HealthKit.
    private var typesToShare: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        if let dist = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            types.insert(dist)
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        return types
    }

    /// The app only writes workouts to HealthKit; it never queries them back, so
    /// no read authorization is requested (avoids an unnecessary "read workouts"
    /// prompt).
    private let typesToRead: Set<HKObjectType> = []

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            debugLog.log("HK", "HealthKit not available on this device")
            return
        }

        debugLog.log("HK", "Requesting HealthKit authorization...")
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            Task { @MainActor in
                self?.isAuthorized = success
                if let error {
                    self?.debugLog.log("HK", "Auth error: \(error.localizedDescription)")
                } else {
                    self?.debugLog.log("HK", "Auth result: \(success)")
                }
            }
        }
    }

    /// Save a finished ride as an outdoor cycling workout with distance, energy,
    /// heart rate and GPS route. Throws without saving anything if a step before
    /// `finishWorkout` fails, so the caller can retry later. The ride ID is the
    /// sync identifier, so a retry after an unrecorded success is a no-op.
    func save(_ ride: Ride) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw WorkoutSaveError.healthDataUnavailable }

        let rideSamples = (ride.samples ?? []).sorted { $0.timestamp < $1.timestamp }
        let startDate = ride.startDate
        let endDate = max(ride.endDate ?? startDate.addingTimeInterval(TimeInterval(ride.duration)), startDate)
        let title = ride.name.isEmpty ? "Giant Buddy" : ride.name

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        let samples = quantitySamples(for: ride, rideSamples: rideSamples, start: startDate, end: endDate)
        let seconds = Int(endDate.timeIntervalSince(startDate))
        debugLog.log("HK", "Saving workout \"\(title)\": \(samples.count) samples, \(seconds)s")

        do {
            try await builder.beginCollection(at: startDate)
            try await builder.addMetadata([
                HKMetadataKeyWorkoutBrandName: title,
                HKMetadataKeySyncIdentifier: ride.id.uuidString,
                HKMetadataKeySyncVersion: 1
            ])
            if !samples.isEmpty {
                try await builder.addSamples(samples)
            }
            try await builder.endCollection(at: endDate)
        } catch {
            builder.discardWorkout()
            throw error
        }

        guard let workout = try await builder.finishWorkout() else {
            throw WorkoutSaveError.finishReturnedNil
        }
        debugLog.log("HK", "Workout saved ✅ duration=\(Int(workout.duration))s")

        await saveRoute(from: rideSamples, for: workout)
    }

    private func quantitySamples(for ride: Ride, rideSamples: [RideSample],
                                 start: Date, end: Date) -> [HKSample] {
        var samples: [HKSample] = []

        // Distance (HealthKit distanceCycling in meters; ride distance is km)
        if ride.totalDistance > 0, let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            samples.append(HKQuantitySample(
                type: distType,
                quantity: HKQuantity(unit: .meter(), doubleValue: ride.totalDistance * 1000.0),
                start: start, end: end
            ))
        }

        // Calories — prefer rider power (human effort), fall back to motor power.
        // power (W) × duration (s) = mechanical work (J); cycling efficiency ~25%,
        // so metabolic cost ≈ work / 0.25; 1 kcal = 4184 J.
        let riderPower = ride.avgRiderPower
        let power = riderPower > 0 ? riderPower : ride.avgPower
        let duration = end.timeIntervalSince(start)
        if power > 0, duration > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let kcal = power * duration / 0.25 / 4184.0
            samples.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: start, end: end
            ))
            let kcalText = String(format: "%.0f", kcal)
            let powerText = String(format: "%.0f", power)
            debugLog.log("HK", "Energy: \(kcalText)kcal from \(powerText)W × \(Int(duration))s")
        }

        // Heart rate relayed from Apple Watch during the ride
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            for sample in rideSamples where sample.heartRate > 0 {
                samples.append(HKQuantitySample(
                    type: hrType,
                    quantity: HKQuantity(unit: bpmUnit, doubleValue: sample.heartRate),
                    start: sample.timestamp, end: sample.timestamp
                ))
            }
        }

        return samples
    }

    /// Attach the GPS route. A failure here is logged but not thrown: the workout
    /// is already saved and the route cannot be re-attached on retry.
    private func saveRoute(from rideSamples: [RideSample], for workout: HKWorkout) async {
        let locations = rideSamples
            .filter { ($0.latitude != 0 || $0.longitude != 0) && $0.horizontalAccuracy >= 0 }
            .map { sample in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                    altitude: sample.altitude,
                    horizontalAccuracy: sample.horizontalAccuracy,
                    // Vertical accuracy isn't stored; reuse horizontal so altitude counts as valid.
                    verticalAccuracy: sample.altitude != 0 ? sample.horizontalAccuracy : -1,
                    course: sample.course,
                    speed: sample.gpsSpeed,
                    timestamp: sample.timestamp
                )
            }
        guard !locations.isEmpty else { return }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        do {
            try await routeBuilder.insertRouteData(locations)
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            debugLog.log("HK", "Route saved ✅ \(locations.count) points")
        } catch {
            debugLog.log("HK", "Route save error: \(error.localizedDescription)")
        }
    }
}
