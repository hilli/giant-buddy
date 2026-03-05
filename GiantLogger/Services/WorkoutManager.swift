import Foundation
import HealthKit
import CoreLocation
import os

/// Manages HealthKit workout lifecycle for outdoor cycling activities.
@MainActor
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

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        self.workoutBuilder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        self.workoutStartDate = Date()

        debugLog.log("HK", "Starting outdoor cycling workout...")

        builder.beginCollection(withStart: Date()) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.debugLog.log("HK", "Begin collection FAILED: \(error.localizedDescription)")
                } else {
                    self?.debugLog.log("HK", "Workout collection started: \(success)")
                }
            }
        }
    }

    /// Add a GPS location to the workout route.
    func addRouteLocation(_ location: CLLocation) {
        routeBuilder?.insertRouteData([location]) { [weak self] success, error in
            if let error {
                Task { @MainActor in
                    self?.debugLog.log("HK", "Route insert error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Stop the workout and save it with ride summary data.
    /// Chains: add samples → endCollection → finishWorkout → finishRoute.
    func stopWorkout(distance: Double, elevationGain: Double, avgPower: Double, duration: TimeInterval) {
        guard let builder = workoutBuilder else {
            debugLog.log("HK", "stopWorkout called but no active builder")
            return
        }
        let endDate = Date()
        let startDate = workoutStartDate ?? endDate.addingTimeInterval(-duration)
        let capturedRouteBuilder = routeBuilder

        // Clear references immediately
        workoutBuilder = nil
        routeBuilder = nil
        workoutStartDate = nil

        debugLog.log("HK", "Stopping workout: dist=\(String(format: "%.2f", distance))km power=\(String(format: "%.0f", avgPower))W dur=\(Int(duration))s")

        // Build samples to add
        var samples: [HKSample] = []

        if distance > 0, let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            let sample = HKQuantitySample(
                type: distType,
                quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: distance),
                start: startDate, end: endDate
            )
            samples.append(sample)
        }

        if avgPower > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let kcal = (avgPower * duration) / 4184.0
            let sample = HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: startDate, end: endDate
            )
            samples.append(sample)
        }

        // Step 1: Add all samples at once
        let addSamples = { (completion: @escaping () -> Void) in
            guard !samples.isEmpty else { completion(); return }
            builder.add(samples) { [weak self] success, error in
                Task { @MainActor in
                    if let error {
                        self?.debugLog.log("HK", "Add samples FAILED: \(error.localizedDescription)")
                    } else {
                        self?.debugLog.log("HK", "Added \(samples.count) samples")
                    }
                    completion()
                }
            }
        }

        // Step 2: End collection (after samples added)
        let endCollection = { (completion: @escaping () -> Void) in
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
        let finishWorkout = { [weak self] in
            builder.finishWorkout { [weak self] workout, error in
                Task { @MainActor in
                    if let error {
                        self?.debugLog.log("HK", "Finish workout FAILED: \(error.localizedDescription)")
                        return
                    }
                    guard let workout else {
                        self?.debugLog.log("HK", "Finish workout returned nil")
                        return
                    }
                    self?.debugLog.log("HK", "Workout saved ✅ duration=\(Int(workout.duration))s")

                    // Step 4: Attach GPS route
                    if let capturedRouteBuilder {
                        Task {
                            do {
                                try await capturedRouteBuilder.finishRoute(with: workout, metadata: nil)
                                await MainActor.run {
                                    self?.debugLog.log("HK", "Route saved ✅")
                                }
                            } catch {
                                await MainActor.run {
                                    self?.debugLog.log("HK", "Route save error: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
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

        builder.beginCollection(withStart: startDate) { [weak self] success, error in
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
