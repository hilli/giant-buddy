import WatchConnectivity
import Combine

struct WatchHeartRateSample: Sendable {
    let timestamp: Date
    let bpm: Double
}

private struct WatchHeartRateUpdate: Sendable {
    let timestamp: Date
    let bpm: Double
    let activeCalories: Double?

    init?(_ payload: [String: Any]) {
        guard let bpm = payload["heartRate"] as? Double, bpm > 0 else { return nil }
        let timestamp = payload["timestamp"] as? Double ?? Date().timeIntervalSince1970
        self.timestamp = Date(timeIntervalSince1970: timestamp)
        self.bpm = bpm
        activeCalories = payload["activeCalories"] as? Double
    }
}

/// Manages WatchConnectivity on the iPhone side, sending telemetry
/// and navigation updates to the paired Apple Watch.
@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private var session: WCSession?
    private var latestContext: [String: Any] = [:]
    private var lastTelemetryContextPush = Date.distantPast
    private var recentHeartRateSamples: [WatchHeartRateSample] = []
    private let transientContextKeys: Set<String> = ["type", "hapticType", "hapticID"]
    private let maxHeartRateSamples = 3_600

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
        latestContext = session?.applicationContext ?? [:]
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
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }

        let previousRecording = latestContext["isRecording"] as? Bool
        let context: [String: Any] = [
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
        var updates = context
        if let navStreet { updates["navStreet"] = navStreet }

        mergeAndSendContext(
            updates,
            forceApplicationContext: previousRecording != isRecording
        )

        if session.isReachable {
            var message = latestContext
            removeTransientContextKeys(from: &message)
            message["type"] = "telemetry"
            session.sendMessage(message, replyHandler: nil) { @Sendable error in
                print("WatchConnectivity: telemetry message failed: \(error.localizedDescription)")
            }
        }
    }

    /// Push current battery/range to Watch for complications (call when bike data arrives).
    func pushBikeDataForComplications() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else {
            print(
                "WatchConnectivity: pushBikeData skipped - paired=\(session?.isPaired ?? false) "
                    + "installed=\(session?.isWatchAppInstalled ?? false)"
            )
            return
        }

        mergeAndSendContext([
            "battery": SharedBikeData.batteryPercent,
            "estimatedRange": SharedBikeData.estimatedRange,
            "bikeName": SharedBikeData.bikeName,
            "isRecording": latestContext["isRecording"] ?? false,
            "totalOdometer": SharedBikeData.totalOdometer,
            "totalUsageHours": SharedBikeData.totalUsageHours
        ], forceApplicationContext: true)
        print(
            "WatchConnectivity: pushed bike data - battery=\(SharedBikeData.batteryPercent)% "
                + "range=\(SharedBikeData.estimatedRange)km odo=\(SharedBikeData.totalOdometer)"
        )
    }

    /// Explicitly notify Watch that recording has stopped, using both
    /// sendMessage (immediate) and updateApplicationContext (persistent).
    func sendRecordingStop() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }

        // Immediate delivery if Watch is reachable
        if session.isReachable {
            session.sendMessage(["type": "recordingStop", "isRecording": false], replyHandler: nil)
        }

        // Also update context as a reliable fallback
        mergeAndSendContext(["isRecording": false], forceApplicationContext: true)
    }
    func sendNavigationUpdate(instruction: String, distance: Double, symbol: String,
                              street: String?, isNavigating: Bool, hapticType: String? = nil) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }

        var message: [String: Any] = [
            "type": "navigation",
            "navInstruction": instruction,
            "navDistance": distance,
            "navSymbol": symbol,
            "isNavigating": isNavigating
        ]
        if let street { message["navStreet"] = street }
        if let hapticType {
            message["hapticType"] = hapticType
            message["hapticID"] = UUID().uuidString
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        } else {
            var persistentMessage = message
            removeTransientContextKeys(from: &persistentMessage)
            mergeAndSendContext(persistentMessage, forceApplicationContext: true)
        }
    }

    func heartRateSamples(since startDate: Date?, through endDate: Date) -> [WatchHeartRateSample] {
        recentHeartRateSamples.filter { sample in
            sample.bpm > 0
                && sample.timestamp <= endDate
                && startDate.map { sample.timestamp >= $0 } != false
        }
    }

    private func mergeAndSendContext(_ updates: [String: Any], forceApplicationContext: Bool) {
        guard let session else { return }
        if latestContext.isEmpty {
            latestContext = session.applicationContext
        }
        removeTransientContextKeys(from: &latestContext)
        for (key, value) in updates {
            guard !transientContextKeys.contains(key) else { continue }
            latestContext[key] = value
        }
        latestContext["lastPush"] = Date().timeIntervalSince1970

        let shouldPush = forceApplicationContext
            || Date().timeIntervalSince(lastTelemetryContextPush) >= 10
        guard shouldPush else { return }

        do {
            try session.updateApplicationContext(latestContext)
            lastTelemetryContextPush = Date()
        } catch {
            print("WatchConnectivity: application context failed: \(error.localizedDescription)")
        }
    }

    private func removeTransientContextKeys(from context: inout [String: Any]) {
        for key in transientContextKeys {
            context.removeValue(forKey: key)
        }
    }

    private func applyHeartRateUpdate(_ update: WatchHeartRateUpdate) {
        heartRate = update.bpm
        appendHeartRateSample(timestamp: update.timestamp, bpm: update.bpm)
        if let calories = update.activeCalories {
            activeCalories = calories
        }
    }

    private func appendHeartRateSample(timestamp: Date, bpm: Double) {
        if recentHeartRateSamples.contains(where: {
            abs($0.timestamp.timeIntervalSince(timestamp)) < 0.001 && $0.bpm == bpm
        }) {
            return
        }
        recentHeartRateSamples.append(WatchHeartRateSample(timestamp: timestamp, bpm: bpm))
        if recentHeartRateSamples.count > maxHeartRateSamples {
            recentHeartRateSamples.removeFirst(recentHeartRateSamples.count - maxHeartRateSamples)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
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
        let command = message["command"] as? String
        let messageType = message["type"] as? String
        let heartRateUpdate = WatchHeartRateUpdate(message)
        let heartRateBatch = (message["samples"] as? [[String: Any]])?.compactMap(WatchHeartRateUpdate.init)
        Task { @MainActor in
            if let command {
                switch command {
                case "startRecording": onStartRecording?()
                case "stopRecording": onStopRecording?()
                default: break
                }
            } else if messageType == "heartRate", let heartRateUpdate {
                self.applyHeartRateUpdate(heartRateUpdate)
            } else if messageType == "heartRateBatch", let heartRateBatch {
                heartRateBatch.forEach { self.applyHeartRateUpdate($0) }
            }
        }
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let messageType = userInfo["type"] as? String
        let heartRateUpdate = WatchHeartRateUpdate(userInfo)
        Task { @MainActor in
            if messageType == "heartRate", let heartRateUpdate {
                self.applyHeartRateUpdate(heartRateUpdate)
            }
        }
    }
}
