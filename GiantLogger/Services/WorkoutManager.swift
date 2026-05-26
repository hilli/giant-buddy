import Foundation
import HealthKit
import CoreLocation
import os
import UIKit

@MainActor
private final class BackgroundTaskHandle {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let debugLog: DebugLogger

    init(name: String, debugLog: DebugLogger) {
        self.debugLog = debugLog
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.debugLog.log("HK", "WARN: background task expired while saving workout")
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// Manages HealthKit workout lifecycle for outdoor cycling activities.
@MainActor
// swiftlint:disable:next type_body_length
class WorkoutManager: ObservableObject {

    @Published var isAuthorized = false

    private let healthStore = HKHealthStore()
    private var workoutBuilder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var workoutStartDate: Date?
    private let logger = Logger(subsystem: "dk.hilli.GiantLogger", category: "Workout")
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

    /// Types we read.
    private var typesToRead: Set<HKObjectType> {
        Set([HKObjectType.workoutType()])
    }

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

    /// Start an outdoor cycling workout.
    func startWorkout() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Prevent double-start: discard any abandoned builder first
        if workoutBuilder != nil {
            debugLog.log("HK", "WARN: startWorkout called with active builder — discarding previous")
            discardWorkout()
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        self.workoutBuilder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        let now = Date()
        self.workoutStartDate = now

        debugLog.log("HK", "Starting outdoor cycling workout...")

        builder.beginCollection(withStart: now) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.debugLog.log("HK", "Begin collection FAILED: \(error.localizedDescription)")
                } else {
                    self?.debugLog.log("HK", "Workout collection started: \(success)")
                }
                // Set brand metadata so Apple Health shows "Giant Buddy"
                do {
                    try await builder.addMetadata(
                        [HKMetadataKeyWorkoutBrandName: "Giant Buddy"]
                    )
                    self?.debugLog.log("HK", "Brand metadata set: Giant Buddy")
                } catch {
                    self?.debugLog.log("HK", "Brand metadata error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Discard the current workout without saving to HealthKit.
    func discardWorkout() {
        guard let builder = workoutBuilder else { return }
        let endDate = Date()
        workoutBuilder = nil
        routeBuilder = nil
        workoutStartDate = nil
        debugLog.log("HK", "Discarding workout (ride was discarded)")
        builder.endCollection(withEnd: endDate) { [weak self] _, _ in
            builder.finishWorkout { [weak self] _, _ in
                // Builder discarded — HealthKit may still save a minimal
                // entry; we delete it immediately.
                Task { @MainActor in
                    self?.debugLog.log("HK", "Discarded workout builder cleaned up")
                }
            }
        }
    }

    /// Add a GPS location to the workout route.
    func addRouteLocation(_ location: CLLocation) {
        routeBuilder?.insertRouteData([location]) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.debugLog.log("HK", "Route insert error: \(error.localizedDescription)")
                }
            }
        }
    }

    // swiftlint:disable function_body_length
    /// Stop the workout and save it with ride summary data.
    /// Chains: add samples → endCollection → finishWorkout → finishRoute.
    /// - Parameters:
    ///   - distance: Total ride distance in km.
    ///   - elevationGain: Total elevation gain in meters.
    ///   - avgMotorPower: Average motor power output in watts.
    ///   - avgRiderPower: Average human pedalling power in watts (torque × cadence × 2π/60).
    ///   - duration: Ride duration in seconds.
    ///   - heartRateSamples: Per-sample HR readings relayed from Apple Watch.
    func stopWorkout(distance: Double, elevationGain: Double,
                     avgMotorPower: Double, avgRiderPower: Double,
                     duration: TimeInterval,
                     heartRateSamples: [(timestamp: Date, bpm: Double)] = []) {
        guard let builder = workoutBuilder else {
            debugLog.log("HK", "stopWorkout called but no active builder")
            return
        }
        let endDate = Date()
        let startDate = workoutStartDate ?? endDate.addingTimeInterval(-duration)
        let capturedRouteBuilder = routeBuilder
        let backgroundTask = BackgroundTaskHandle(name: "save-workout", debugLog: debugLog)

        // Clear references immediately
        workoutBuilder = nil
        routeBuilder = nil
        workoutStartDate = nil

        debugLog.log("HK", "Stopping workout: dist=\(String(format: "%.2f", distance))km motorW=\(String(format: "%.0f", avgMotorPower)) riderW=\(String(format: "%.0f", avgRiderPower)) dur=\(Int(duration))s")

        // Build samples to add
        var samples: [HKSample] = []

        // Distance (in meters — HealthKit distanceCycling expects meters)
        if distance > 0, let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            let distanceMeters = distance * 1000.0
            let sample = HKQuantitySample(
                type: distType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                start: startDate, end: endDate
            )
            samples.append(sample)
            debugLog.log("HK", "Distance sample: \(String(format: "%.0f", distanceMeters))m (\(String(format: "%.2f", distance))km)")
        }

        // Calories — prefer rider power (human effort), fall back to motor power
        let powerForCalories = avgRiderPower > 0 ? avgRiderPower : avgMotorPower
        if powerForCalories > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            // power (W) × duration (s) = energy (J); 1 kcal = 4184 J
            // Cycling efficiency ~25%, so total metabolic cost ≈ mechanical work / 0.25
            let mechanicalWork = powerForCalories * duration
            let metabolicEnergy = mechanicalWork / 0.25
            let kcal = metabolicEnergy / 4184.0
            let sample = HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: startDate, end: endDate
            )
            samples.append(sample)
            debugLog.log("HK", "Energy sample: \(String(format: "%.0f", kcal))kcal from \(String(format: "%.0f", powerForCalories))W × \(Int(duration))s")
        }

        // Add individual heart rate samples
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            for hr in heartRateSamples where hr.bpm > 0 {
                let sample = HKQuantitySample(
                    type: hrType,
                    quantity: HKQuantity(unit: bpmUnit, doubleValue: hr.bpm),
                    start: hr.timestamp, end: hr.timestamp.addingTimeInterval(2)
                )
                samples.append(sample)
            }
            if !heartRateSamples.isEmpty {
                debugLog.log("HK", "Including \(heartRateSamples.filter { $0.bpm > 0 }.count) HR samples")
            }
        }

        // Step 1: Add all samples at once
        let addSamples: (@escaping @Sendable () -> Void) -> Void = { completion in
            guard !samples.isEmpty else { completion(); return }
            let sampleCount = samples.count
            builder.add(samples) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.debugLog.log("HK", "Add samples FAILED: \(error.localizedDescription)")
                    } else {
                        self?.debugLog.log("HK", "Added \(sampleCount) samples")
                    }
                    completion()
                }
            }
        }

        // Step 2: End collection (after samples added)
        let endCollection: @Sendable (@escaping @Sendable () -> Void) -> Void = { completion in
            builder.endCollection(withEnd: endDate) { [weak self] success, error in
                Task { @MainActor in
                    if let error {
                        self?.debugLog.log("HK", "End collection FAILED: \(error.localizedDescription)")
                    } else {
                        self?.debugLog.log("HK", "Collection ended: \(success)")
                    }
                    completion()
                }
            }
        }

        // Step 3: Finish workout (after collection ended)
        let finishWorkout: @Sendable () -> Void = { [weak self] in
            builder.finishWorkout { [weak self] workout, error in
                Task { @MainActor in
                    if let error {
                        self?.debugLog.log("HK", "Finish workout FAILED: \(error.localizedDescription)")
                        backgroundTask.end()
                        return
                    }
                    guard let workout else {
                        self?.debugLog.log("HK", "Finish workout returned nil")
                        backgroundTask.end()
                        return
                    }
                    self?.debugLog.log("HK", "Workout saved ✅ duration=\(Int(workout.duration))s")

                    // Step 4: Attach GPS route
                    guard let capturedRouteBuilder else {
                        backgroundTask.end()
                        return
                    }

                    do {
                        try await capturedRouteBuilder.finishRoute(with: workout, metadata: nil)
                        self?.debugLog.log("HK", "Route saved ✅")
                    } catch {
                        self?.debugLog.log("HK", "Route save error: \(error.localizedDescription)")
                    }
                    backgroundTask.end()
                }
            }
        }

        // Chain: addSamples → endCollection → finishWorkout
        addSamples {
            endCollection {
                finishWorkout()
            }
        }
    }
    // swiftlint:enable function_body_length

    /// Inject a sample 10-minute cycling workout for debugging.
    func injectSampleWorkout() {
        guard HKHealthStore.isHealthDataAvailable() else {
            debugLog.log("HK", "HealthKit not available")
            return
        }

        debugLog.log("HK", "Injecting sample workout...")

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-600) // 10 minutes ago

        builder.beginCollection(withStart: startDate) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.debugLog.log("HK", "Sample begin FAILED: \(error.localizedDescription)")
                }
                return
            }

            // Build samples
            var samples: [HKSample] = []
            if let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
                samples.append(HKQuantitySample(
                    type: distType,
                    quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: 5.0),
                    start: startDate, end: endDate
                ))
            }
            if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                samples.append(HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 120.0),
                    start: startDate, end: endDate
                ))
            }

            builder.add(samples) { [weak self] _, error in
                if let error {
                    Task { @MainActor in
                        self?.debugLog.log("HK", "Sample add FAILED: \(error.localizedDescription)")
                    }
                    return
                }

                Task { @MainActor in
                    self?.debugLog.log("HK", "Sample: added distance + energy")
                }

                builder.endCollection(withEnd: endDate) { [weak self] _, error in
                    if let error {
                        Task { @MainActor in
                            self?.debugLog.log("HK", "Sample end FAILED: \(error.localizedDescription)")
                        }
                        return
                    }

                    builder.finishWorkout { [weak self] workout, error in
                        Task { @MainActor in
                            if let error {
                                self?.debugLog.log("HK", "Sample finish FAILED: \(error.localizedDescription)")
                            } else {
                                self?.debugLog.log("HK", "Sample workout saved ✅ \(workout?.duration ?? 0)s")
                            }
                        }
                    }
                }
            }
        }
    }
}
