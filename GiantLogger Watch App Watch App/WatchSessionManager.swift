import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit
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
        if let val = context["isRecording"] as? Bool { isRecording = val }
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
