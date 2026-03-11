import WatchConnectivity
import Combine

/// Manages WatchConnectivity on the iPhone side, sending telemetry
/// and navigation updates to the paired Apple Watch.
@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private var session: WCSession?

    // Heart rate from Watch
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0

    // Callbacks for Watch commands
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Send latest telemetry to Watch as application context.
    func sendTelemetry( // swiftlint:disable:this function_parameter_count
        speed: Double, battery: Int, distance: Double, duration: Int,
        cadence: Double, watts: Double, isRecording: Bool, bikeName: String,
        isNavigating: Bool = false, navInstruction: String = "",
        navDistance: Double = 0, navSymbol: String = "arrow.up", navStreet: String? = nil
    ) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

        var context: [String: Any] = [
            "speed": speed,
            "battery": battery,
            "distance": distance,
            "duration": duration,
            "cadence": cadence,
            "watts": watts,
            "isRecording": isRecording,
            "bikeName": bikeName,
            "estimatedRange": SharedBikeData.estimatedRange,
            "totalOdometer": SharedBikeData.totalOdometer,
            "totalUsageHours": SharedBikeData.totalUsageHours,
            "isNavigating": isNavigating,
            "navInstruction": navInstruction,
            "navDistance": navDistance,
            "navSymbol": navSymbol
        ]
        if let navStreet { context["navStreet"] = navStreet }

        try? session.updateApplicationContext(context)
    }

    /// Push current battery/range to Watch for complications (call when bike data arrives).
    func pushBikeDataForComplications() {
        guard let session, session.isPaired, session.isWatchAppInstalled else {
            print("WatchConnectivity: pushBikeData skipped - paired=\(session?.isPaired ?? false) installed=\(session?.isWatchAppInstalled ?? false)")
            return
        }

        // Merge into existing context so we don't overwrite other fields
        var context = session.applicationContext
        context["battery"] = SharedBikeData.batteryPercent
        context["estimatedRange"] = SharedBikeData.estimatedRange
        context["bikeName"] = SharedBikeData.bikeName
        context["isRecording"] = context["isRecording"] ?? false
        context["totalOdometer"] = SharedBikeData.totalOdometer
        context["totalUsageHours"] = SharedBikeData.totalUsageHours
        context["lastPush"] = Date().timeIntervalSince1970

        do {
            try session.updateApplicationContext(context)
            print("WatchConnectivity: pushed bike data - battery=\(SharedBikeData.batteryPercent)% range=\(SharedBikeData.estimatedRange)km odo=\(SharedBikeData.totalOdometer)")
        } catch {
            print("WatchConnectivity: pushBikeData FAILED: \(error)")
        }
    }

    /// Explicitly notify Watch that recording has stopped, using both
    /// sendMessage (immediate) and updateApplicationContext (persistent).
    func sendRecordingStop() {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

        // Immediate delivery if Watch is reachable
        if session.isReachable {
            session.sendMessage(["type": "recordingStop", "isRecording": false], replyHandler: nil)
        }

        // Also update context as a reliable fallback
        var context = session.applicationContext
        context["isRecording"] = false
        context["lastPush"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(context)
    }
    func sendNavigationUpdate(instruction: String, distance: Double, symbol: String,
                              street: String?, isNavigating: Bool, hapticType: String? = nil) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

        var message: [String: Any] = [
            "type": "navigation",
            "navInstruction": instruction,
            "navDistance": distance,
            "navSymbol": symbol,
            "isNavigating": isNavigating
        ]
        if let street { message["navStreet"] = street }
        if let hapticType { message["hapticType"] = hapticType }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        } else {
            var context = session.applicationContext
            for (key, value) in message { context[key] = value }
            try? session.updateApplicationContext(context)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error {
            print("WatchConnectivity: activation failed: \(error)")
        }
        if state == .activated {
            Task { @MainActor in
                self.pushBikeDataForComplications()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let command = message["command"] as? String {
                switch command {
                case "startRecording": onStartRecording?()
                case "stopRecording": onStopRecording?()
                default: break
                }
            } else if let type = message["type"] as? String, type == "heartRate" {
                if let hr = message["heartRate"] as? Double { self.heartRate = hr }
                if let cal = message["activeCalories"] as? Double { self.activeCalories = cal }
            }
        }
    }
}
