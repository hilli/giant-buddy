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
    private var telemetryTimeoutTask: Task<Void, Never>?
    private var pendingHeartRateSamples: [HeartRatePayload] = []
    private var healthKitAuthorizationRequested = false
    private var lastHapticID: String?
    private let maxPendingHeartRateSamples = 300

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

    func requestHealthKitAuth(completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?(false)
            return
        }
        healthKitAuthorizationRequested = true
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
            Task { @MainActor in
                completion?(success)
            }
        }
    }

    func startWorkoutSession() {
        guard HKHealthStore.isHealthDataAvailable(),
              workoutSession == nil else { return }

        if !healthKitAuthorizationRequested {
            requestHealthKitAuth { [weak self] success in
                guard success else { return }
                Task { @MainActor in
                    self?.startWorkoutSession()
                }
            }
            return
        }

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
        // Discard the workout — the phone's WorkoutManager is the single source
        // of truth for HealthKit workouts (it has GPS route, distance, calories).
        // We only run the watch session to access live HR from the sensors.
        workoutBuilder?.discardWorkout()
        workoutSession = nil
        workoutBuilder = nil
        heartRate = 0
        activeCalories = 0
    }

    private func handleRecordingStop() {
        isRecording = false
        telemetryTimeoutTask?.cancel()
        telemetryTimeoutTask = nil
        stopWorkoutSession()
        speed = 0
        cadence = 0
        watts = 0
    }

    /// Reset the telemetry timeout. If no update arrives within 10 seconds
    /// while recording, assume iPhone stopped and auto-stop on Watch.
    private func resetTelemetryTimeout() {
        telemetryTimeoutTask?.cancel()
        telemetryTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, isRecording else { return }
            print("WatchSession: telemetry timeout — auto-stopping recording")
            handleRecordingStop()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func updateFromPayload(_ payload: WatchPayload) {
        if let val = payload.speed { speed = val }
        if let val = payload.battery {
            battery = val
            persistForComplications(battery: val, range: payload.estimatedRange)
        }
        if let val = payload.distance { distance = val }
        if let val = payload.duration { duration = val }
        if let val = payload.cadence { cadence = val }
        if let val = payload.watts { watts = val }
        if let val = payload.isRecording {
            let wasRecording = isRecording
            isRecording = val
            if val && !wasRecording {
                startWorkoutSession()
                resetTelemetryTimeout()
            } else if val {
                resetTelemetryTimeout()
            } else if !val && wasRecording {
                handleRecordingStop()
            }
        }
        if let val = payload.bikeName { bikeName = val }
        if let val = payload.estimatedRange { estimatedRange = val }
        if let val = payload.totalOdometer { totalOdometer = val }
        if let val = payload.totalUsageHours { totalUsageHours = val }
        if let val = payload.isNavigating { isNavigating = val }
        if let val = payload.navInstruction { navInstruction = val }
        if let val = payload.navDistance { navDistance = val }
        if let val = payload.navSymbol { navSymbol = val }
        navStreet = payload.navStreet
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
        let isReachable = session.isReachable
        let context = session.receivedApplicationContext
        let payload = WatchPayload(context)
        print("WatchSession: activated state=\(state.rawValue) reachable=\(isReachable)")
        print("WatchSession: cached context has \(context.count) keys: \(Array(context.keys))")
        Task { @MainActor in
            isPhoneReachable = isReachable
            // Load last received context so Watch has data immediately
            if !payload.isEmpty {
                updateFromPayload(payload)
            }
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let battery = applicationContext["battery"] ?? "nil"
        let payload = WatchPayload(applicationContext)
        print("WatchSession: received context with \(applicationContext.count) keys - battery=\(battery)")
        Task { @MainActor in
            updateFromPayload(payload)
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = WatchPayload(message)
        Task { @MainActor in
            let messageType = payload.messageType
            if messageType == "navigation" || messageType == "telemetry" {
                updateFromPayload(payload)
                if messageType == "navigation", let hapticType = payload.hapticType {
                    guard let hapticID = payload.hapticID, hapticID != lastHapticID else { return }
                    lastHapticID = hapticID
                    switch hapticType {
                    case "turn":
                        WKInterfaceDevice.current().play(.directionUp)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            WKInterfaceDevice.current().play(.directionUp)
                        }
                    case "arrival":
                        WKInterfaceDevice.current().play(.success)
                    default:
                        break
                    }
                }
            } else if messageType == "recordingStop" {
                print("WatchSession: received recordingStop message")
                handleRecordingStop()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            isPhoneReachable = isReachable
            if isReachable {
                flushPendingHeartRateSamples()
            }
        }
    }
}

// MARK: - HealthKit Workout Delegates

extension WatchSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("WatchHK: workout state \(fromState.rawValue) → \(toState.rawValue)")
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("WatchHK: workout error: \(error.localizedDescription)")
    }
}

extension WatchSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        var collectedBPM: Double?
        var collectedCalories: Double?
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if quantityType == HKQuantityType(.heartRate),
               let stats = workoutBuilder.statistics(for: quantityType),
               let bpm = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
               bpm > 0 {
                collectedBPM = bpm
            }

            if quantityType == HKQuantityType(.activeEnergyBurned),
               let stats = workoutBuilder.statistics(for: quantityType),
               let cal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                collectedCalories = cal
            }
        }

        Task { @MainActor in
            if let collectedBPM {
                heartRate = collectedBPM
                sendHeartRate(collectedBPM)
            }

            if let collectedCalories {
                activeCalories = collectedCalories
            }
        }
    }

    private func sendHeartRate(_ bpm: Double) {
        let payload = HeartRatePayload(
            bpm: bpm,
            activeCalories: activeCalories,
            timestamp: Date().timeIntervalSince1970
        )

        guard let session else { return }
        if session.isReachable {
            session.sendMessage(payload.dictionary, replyHandler: nil) { @Sendable [weak self] error in
                print("WatchSession: HR message failed: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.queueHeartRateSample(payload)
                }
            }
        } else {
            queueHeartRateSample(payload)
            session.transferUserInfo(payload.dictionary)
        }
    }

    private func queueHeartRateSample(_ payload: HeartRatePayload) {
        pendingHeartRateSamples.append(payload)
        if pendingHeartRateSamples.count > maxPendingHeartRateSamples {
            pendingHeartRateSamples.removeFirst(pendingHeartRateSamples.count - maxPendingHeartRateSamples)
        }
    }

    private func flushPendingHeartRateSamples() {
        guard let session, session.isReachable, !pendingHeartRateSamples.isEmpty else { return }
        let samples = pendingHeartRateSamples
        pendingHeartRateSamples.removeAll()
        session.sendMessage([
            "type": "heartRateBatch",
            "samples": samples.map(\.dictionary)
        ], replyHandler: nil) { @Sendable [weak self] error in
            print("WatchSession: HR batch failed: \(error.localizedDescription)")
            Task { @MainActor in
                samples.forEach { self?.queueHeartRateSample($0) }
            }
        }
    }
}
