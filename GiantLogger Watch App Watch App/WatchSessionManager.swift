import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit
import Combine
import HealthKit

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
    @Published var estimatedRange: Int = 0
    @Published var totalOdometer: Double = 0
    @Published var totalUsageHours: Int = 0

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
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
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

    // MARK: - HealthKit Workout

    func requestHealthKitAuth() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        healthStore.requestAuthorization(toShare: share, read: read) { success, error in
            if let error {
                print("WatchHK: auth error: \(error.localizedDescription)")
            } else {
                print("WatchHK: auth result: \(success)")
            }
        }
    }

    func startWorkoutSession() {
        guard HKHealthStore.isHealthDataAvailable(),
              workoutSession == nil else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, error in
                if let error {
                    print("WatchHK: begin collection error: \(error.localizedDescription)")
                } else {
                    print("WatchHK: workout started, collecting HR")
                }
            }
        } catch {
            print("WatchHK: failed to create workout session: \(error)")
        }
    }

    func stopWorkoutSession() {
        guard let session = workoutSession else { return }
        session.end()
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.workoutBuilder?.finishWorkout { _, error in
                if let error {
                    print("WatchHK: finish workout error: \(error)")
                } else {
                    print("WatchHK: workout saved")
                }
            }
        }
        workoutSession = nil
        workoutBuilder = nil
        heartRate = 0
        activeCalories = 0
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func updateFromContext(_ context: [String: Any]) {
        if let val = context["speed"] as? Double { speed = val }
        if let val = context["battery"] as? Int {
            battery = val
            persistForComplications(battery: val, range: context["estimatedRange"] as? Int)
        }
        if let val = context["distance"] as? Double { distance = val }
        if let val = context["duration"] as? Int { duration = val }
        if let val = context["cadence"] as? Double { cadence = val }
        if let val = context["watts"] as? Double { watts = val }
        if let val = context["isRecording"] as? Bool {
            let wasRecording = isRecording
            isRecording = val
            if val && !wasRecording {
                startWorkoutSession()
            } else if !val && wasRecording {
                stopWorkoutSession()
            }
        }
        if let val = context["bikeName"] as? String { bikeName = val }
        if let val = context["estimatedRange"] as? Int { estimatedRange = val }
        if let val = context["totalOdometer"] as? Double { totalOdometer = val }
        if let val = context["totalUsageHours"] as? Int { totalUsageHours = val }
        if let val = context["isNavigating"] as? Bool { isNavigating = val }
        if let val = context["navInstruction"] as? String { navInstruction = val }
        if let val = context["navDistance"] as? Double { navDistance = val }
        if let val = context["navSymbol"] as? String { navSymbol = val }
        navStreet = context["navStreet"] as? String
    }

    private func persistForComplications(battery: Int, range: Int?) {
        let defaults = UserDefaults(suiteName: "group.dk.hilli.GiantLogger")
        defaults?.set(battery, forKey: "batteryPercent")
        defaults?.set(Date(), forKey: "lastConnected")
        if let range, range > 0 {
            defaults?.set(range, forKey: "estimatedRange")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WatchSession: activation failed: \(error)")
        }
        print("WatchSession: activated state=\(state.rawValue) reachable=\(session.isReachable)")
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            // Load last received context so Watch has data immediately
            let context = session.receivedApplicationContext
            print("WatchSession: cached context has \(context.count) keys: \(Array(context.keys))")
            if !context.isEmpty {
                updateFromContext(context)
            }
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("WatchSession: received context with \(applicationContext.count) keys - battery=\(applicationContext["battery"] ?? "nil")")
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

// MARK: - HealthKit Workout Delegates

extension WatchSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState, date: Date) {
        print("WatchHK: workout state \(fromState.rawValue) → \(toState.rawValue)")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didFailWithError error: Error) {
        print("WatchHK: workout error: \(error.localizedDescription)")
    }
}

extension WatchSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }

                if quantityType == HKQuantityType(.heartRate),
                   let stats = workoutBuilder.statistics(for: quantityType),
                   let hr = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                   hr > 0 {
                    heartRate = hr
                    sendHeartRate(hr)
                }

                if quantityType == HKQuantityType(.activeEnergyBurned),
                   let stats = workoutBuilder.statistics(for: quantityType),
                   let cal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    activeCalories = cal
                }
            }
        }
    }

    private func sendHeartRate(_ hr: Double) {
        guard let session, session.isReachable else { return }
        session.sendMessage([
            "type": "heartRate",
            "heartRate": hr,
            "activeCalories": activeCalories
        ], replyHandler: nil)
    }
}
