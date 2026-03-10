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
            "isNavigating": isNavigating,
            "navInstruction": navInstruction,
            "navDistance": navDistance,
            "navSymbol": navSymbol
        ]
        if let navStreet { context["navStreet"] = navStreet }

        try? session.updateApplicationContext(context)
    }

    /// Send navigation instruction update (triggers haptic on Watch).
    func sendNavigationUpdate(instruction: String, distance: Double, symbol: String,
                              street: String?, isNavigating: Bool) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

        var message: [String: Any] = [
            "type": "navigation",
            "navInstruction": instruction,
            "navDistance": distance,
            "navSymbol": symbol,
            "isNavigating": isNavigating
        ]
        if let street { message["navStreet"] = street }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        } else {
            // Fall back to application context when Watch is not reachable
            var context = session.applicationContext
            for (key, value) in message { context[key] = value }
            try? session.updateApplicationContext(context)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error: Error?) {
        if let error {
            print("WatchConnectivity: activation failed: \(error)")
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
