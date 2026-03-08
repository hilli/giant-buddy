import SwiftUI
import WatchConnectivity
import WatchKit
import HealthKit
import Combine

/// Manages WatchConnectivity on the Watch side, receiving telemetry
/// and navigation updates from the paired iPhone.
@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    // Telemetry
    @Published var speed: Double = 0
    @Published var battery: Int = 0
    @Published var distance: Double = 0
    @Published var duration: Int = 0
    @Published var cadence: Double = 0
    @Published var watts: Double = 0
    @Published var isRecording: Bool = false
    @Published var bikeName: String = "Giant E-Bike"

    // Heart rate / workout
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0

    // Navigation
    @Published var isNavigating: Bool = false
    @Published var navInstruction: String = ""
    @Published var navDistance: Double = 0
    @Published var navSymbol: String = "arrow.up"
    @Published var navStreet: String?

    // Connection
    @Published var isPhoneReachable: Bool = false

    private var session: WCSession?
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
        requestHealthKitPermissions()
    }

    // MARK: - HealthKit Workout

    func startWorkout() {
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            workoutBuilder?.delegate = self
            workoutSession?.delegate = self

            workoutSession?.startActivity(with: .now)
            Task {
                try await workoutBuilder?.beginCollection(at: .now)
            }
        } catch {
            print("WatchSession: Failed to start workout: \(error)")
        }
    }

    func stopWorkout() {
        workoutSession?.end()
        Task {
            try await workoutBuilder?.endCollection(at: .now)
            try await workoutBuilder?.finishWorkout()
        }
        workoutSession = nil
        workoutBuilder = nil
        heartRate = 0
        activeCalories = 0
    }

    func requestHealthKitPermissions() {
        let readTypes: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        let shareTypes: Set<HKSampleType> = [
            HKQuantityType.workoutType()
        ]
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            if let error { print("HealthKit auth failed: \(error)") }
        }
    }

    var formattedDuration: String {
        let hours = duration / 3600
        let mins = (duration % 3600) / 60
        let secs = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    func sendCommand(_ command: String) {
        guard let session, session.isReachable else { return }
        session.sendMessage(["command": command], replyHandler: nil)
    }

    func startRecording() { sendCommand("startRecording") }
    func stopRecording() { sendCommand("stopRecording") }

    // swiftlint:disable:next cyclomatic_complexity
    private func updateFromContext(_ context: [String: Any]) {
        if let val = context["speed"] as? Double { speed = val }
        if let val = context["battery"] as? Int { battery = val }
        if let val = context["distance"] as? Double { distance = val }
        if let val = context["duration"] as? Int { duration = val }
        if let val = context["cadence"] as? Double { cadence = val }
        if let val = context["watts"] as? Double { watts = val }
        if let val = context["isRecording"] as? Bool {
            let wasRecording = isRecording
            isRecording = val
            if val && !wasRecording {
                startWorkout()
            } else if !val && wasRecording {
                stopWorkout()
            }
        }
        if let val = context["bikeName"] as? String { bikeName = val }
        if let val = context["isNavigating"] as? Bool { isNavigating = val }
        if let val = context["navInstruction"] as? String { navInstruction = val }
        if let val = context["navDistance"] as? Double { navDistance = val }
        if let val = context["navSymbol"] as? String { navSymbol = val }
        navStreet = context["navStreet"] as? String
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WatchSession: activation failed: \(error)")
        }
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            updateFromContext(applicationContext)
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if message["type"] as? String == "navigation" {
                updateFromContext(message)
                WKInterfaceDevice.current().play(.directionUp)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // No-op for now
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if let stats = workoutBuilder.statistics(for: quantityType) {
                Task { @MainActor in
                    switch quantityType {
                    case HKQuantityType(.heartRate):
                        let hr = stats.mostRecentQuantity()?
                            .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
                        heartRate = hr
                        sendHeartRate(hr, calories: activeCalories)
                    case HKQuantityType(.activeEnergyBurned):
                        activeCalories = stats.sumQuantity()?
                            .doubleValue(for: .kilocalorie()) ?? 0
                        sendHeartRate(heartRate, calories: activeCalories)
                    default: break
                    }
                }
            }
        }
    }

    private func sendHeartRate(_ hr: Double, calories: Double) {
        guard let session, session.isReachable else { return }
        session.sendMessage([
            "type": "heartRate",
            "heartRate": hr,
            "activeCalories": calories
        ], replyHandler: nil)
    }
}
