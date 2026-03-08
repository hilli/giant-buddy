import Foundation
import CoreLocation
import CoreMotion
import AudioToolbox
import UIKit

/// Emergency contact stored in UserDefaults.
struct EmergencyContact: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var phone: String
}

/// Monitors accelerometer data for sudden impacts and triggers crash alerts.
@MainActor
class CrashDetector: ObservableObject {

    @Published var isCrashDetected = false
    @Published var countdownSeconds: Int = 60
    @Published var isMonitoring = false

    private let motionManager: CMMotionManager
    private let motionQueue = OperationQueue()
    private var countdownTask: Task<Void, Never>?
    private var postImpactTask: Task<Void, Never>?
    private var lastSignificantMotionDate: Date?

    // Accumulate recent magnitudes for variance check after impact
    private var recentMagnitudes: [Double] = []
    private var impactDetected = false

    private let impactThreshold: Double = 3.0  // g-force
    private let postImpactWait: TimeInterval = 10.0
    private let varianceThreshold: Double = 0.05
    private let countdownDuration: Int = 60

    var isTestMode = false
    var locationProvider: (() -> CLLocation?)?

    init() {
        motionManager = CMMotionManager()
        motionManager.accelerometerUpdateInterval = 0.1  // 10 Hz
        motionQueue.name = "com.giantlogger.crashdetector"
        motionQueue.maxConcurrentOperationCount = 1
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard motionManager.isAccelerometerAvailable else {
            print("CrashDetector: Accelerometer not available")
            return
        }

        isMonitoring = true
        impactDetected = false
        recentMagnitudes = []

        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self, let data else { return }
            let mag = Self.magnitude(data.acceleration)

            Task { @MainActor in
                self.processAcceleration(magnitude: mag)
            }
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        impactDetected = false
        recentMagnitudes = []
        cancelCountdown()
    }

    /// User dismisses the crash alert (false alarm).
    func dismissCrashAlert() {
        cancelCountdown()
        isCrashDetected = false
        impactDetected = false
        recentMagnitudes = []
    }

    /// Send emergency alert with current GPS coordinates.
    func sendEmergencyAlert(location: CLLocation?) {
        let contacts = Self.loadEmergencyContacts()
        guard !contacts.isEmpty else { return }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        var body = "⚠️ CRASH DETECTED – GiantLogger\nTime: \(timestamp)"

        if let loc = location {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            body += "\nLocation: https://maps.google.com/?q=\(lat),\(lon)"
        } else {
            body += "\nLocation: unavailable"
        }

        let phones = contacts.map { $0.phone }.joined(separator: ",")
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body

        if let url = URL(string: "sms:\(phones)&body=\(encoded)") {
            UIApplication.shared.open(url)
        }

        isCrashDetected = false
    }

    /// Trigger a test crash alert (countdown only, no SMS).
    func triggerTestAlert() {
        isTestMode = true
        startCountdown()
    }

    // MARK: - Emergency Contact Persistence

    static func loadEmergencyContacts() -> [EmergencyContact] {
        guard let data = UserDefaults.standard.data(forKey: "emergencyContacts") else { return [] }
        return (try? JSONDecoder().decode([EmergencyContact].self, from: data)) ?? []
    }

    static func saveEmergencyContacts(_ contacts: [EmergencyContact]) {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: "emergencyContacts")
        }
    }

    // MARK: - Private

    private func processAcceleration(magnitude: Double) {
        if impactDetected {
            recentMagnitudes.append(magnitude)
            return
        }

        if magnitude > impactThreshold {
            impactDetected = true
            recentMagnitudes = []
            lastSignificantMotionDate = Date()

            postImpactTask = Task {
                try? await Task.sleep(for: .seconds(postImpactWait))
                guard !Task.isCancelled else { return }
                evaluatePostImpact()
            }
        }
    }

    private func evaluatePostImpact() {
        let variance = Self.computeVariance(recentMagnitudes)
        impactDetected = false
        recentMagnitudes = []

        if variance < varianceThreshold {
            // Device is stationary → likely a crash
            startCountdown()
        }
    }

    private func startCountdown() {
        isCrashDetected = true
        countdownSeconds = countdownDuration
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))

        countdownTask = Task {
            while countdownSeconds > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdownSeconds -= 1

                // Haptic feedback every 5 seconds
                if countdownSeconds % 5 == 0, countdownSeconds > 0 {
                    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                }
            }

            if !Task.isCancelled, countdownSeconds <= 0 {
                if isTestMode {
                    isTestMode = false
                    isCrashDetected = false
                } else {
                    // Actual emergency — send alert
                    sendEmergencyAlert(location: locationProvider?())
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        postImpactTask?.cancel()
        postImpactTask = nil
        isTestMode = false
    }

    private static func magnitude(_ accel: CMAcceleration) -> Double {
        sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
    }

    private static func computeVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquaredDiff = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sumSquaredDiff / Double(values.count - 1)
    }
}
