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

    /// Types we need to write to HealthKit.
    private var typesToShare: Set<HKSampleType> {
        let types: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        return Set(types)
    }

    /// Types we read (none required, but keeps the auth dialog balanced).
    private var typesToRead: Set<HKObjectType> {
        let types: [HKObjectType] = [
            HKObjectType.workoutType()
        ]
        return Set(types)
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit not available on this device")
            return
        }

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            Task { @MainActor in
                self?.isAuthorized = success
                if let error {
                    self?.logger.error("HealthKit auth error: \(error.localizedDescription)")
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

        builder.beginCollection(withStart: Date()) { success, error in
            if let error {
                Task { @MainActor in
                    self.logger.error("Failed to begin workout collection: \(error.localizedDescription)")
                }
            }
        }
        logger.info("Started outdoor cycling workout")
    }

    /// Add a GPS location to the workout route.
    func addRouteLocation(_ location: CLLocation) {
        routeBuilder?.insertRouteData([location]) { success, error in
            if let error {
                Task { @MainActor in
                    self.logger.error("Failed to insert route data: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Stop the workout and save it with ride summary data.
    func stopWorkout(distance: Double, elevationGain: Double, avgPower: Double, duration: TimeInterval) {
        guard let builder = workoutBuilder else { return }
        let endDate = Date()

        // Add distance sample
        if distance > 0, let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            let distanceQuantity = HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: distance)
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: distanceQuantity,
                start: workoutStartDate ?? endDate.addingTimeInterval(-duration),
                end: endDate
            )
            builder.add([distanceSample]) { _, error in
                if let error {
                    Task { @MainActor in
                        self.logger.error("Failed to add distance: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Add active energy from avg power × duration (1W = 1J/s, 1kcal ≈ 4184J)
        if avgPower > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let joules = avgPower * duration
            let kcal = joules / 4184.0
            let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
            let energySample = HKQuantitySample(
                type: energyType,
                quantity: energyQuantity,
                start: workoutStartDate ?? endDate.addingTimeInterval(-duration),
                end: endDate
            )
            builder.add([energySample]) { _, error in
                if let error {
                    Task { @MainActor in
                        self.logger.error("Failed to add energy: \(error.localizedDescription)")
                    }
                }
            }
        }

        // End collection and finish workout
        let capturedRouteBuilder = routeBuilder
        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            guard success else {
                Task { @MainActor in
                    self?.logger.error("Failed to end collection: \(error?.localizedDescription ?? "unknown")")
                }
                return
            }

            builder.finishWorkout { [weak self] workout, error in
                if let error {
                    Task { @MainActor in
                        self?.logger.error("Failed to finish workout: \(error.localizedDescription)")
                    }
                    return
                }

                guard let workout else { return }
                Task { @MainActor in
                    self?.logger.info("Saved workout: \(workout.duration)s, \(distance)km")
                }

                // Attach GPS route to the workout
                capturedRouteBuilder?.finishRoute(with: workout, metadata: nil) { [weak self] route, error in
                    if let error {
                        Task { @MainActor [weak self] in
                            self?.logger.error("Failed to save route: \(error.localizedDescription)")
                        }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.logger.info("Saved workout route")
                        }
                    }
                }
            }
        }

        workoutBuilder = nil
        routeBuilder = nil
        workoutStartDate = nil
    }
}
