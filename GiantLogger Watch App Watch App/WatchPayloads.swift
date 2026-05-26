import Foundation

struct WatchPayload: Sendable {
    let messageType: String?
    let hapticType: String?
    let hapticID: String?
    let speed: Double?
    let battery: Int?
    let distance: Double?
    let duration: Int?
    let cadence: Double?
    let watts: Double?
    let isRecording: Bool?
    let bikeName: String?
    let estimatedRange: Int?
    let totalOdometer: Double?
    let totalUsageHours: Int?
    let isNavigating: Bool?
    let navInstruction: String?
    let navDistance: Double?
    let navSymbol: String?
    let navStreet: String?

    nonisolated init(_ context: [String: Any]) {
        messageType = context["type"] as? String
        hapticType = context["hapticType"] as? String
        hapticID = context["hapticID"] as? String
        speed = context["speed"] as? Double
        battery = context["battery"] as? Int
        distance = context["distance"] as? Double
        duration = context["duration"] as? Int
        cadence = context["cadence"] as? Double
        watts = context["watts"] as? Double
        isRecording = context["isRecording"] as? Bool
        bikeName = context["bikeName"] as? String
        estimatedRange = context["estimatedRange"] as? Int
        totalOdometer = context["totalOdometer"] as? Double
        totalUsageHours = context["totalUsageHours"] as? Int
        isNavigating = context["isNavigating"] as? Bool
        navInstruction = context["navInstruction"] as? String
        navDistance = context["navDistance"] as? Double
        navSymbol = context["navSymbol"] as? String
        navStreet = context["navStreet"] as? String
    }

    var isEmpty: Bool {
        speed == nil && battery == nil && distance == nil && duration == nil
            && cadence == nil && watts == nil && isRecording == nil
            && bikeName == nil && estimatedRange == nil && totalOdometer == nil
            && totalUsageHours == nil && isNavigating == nil
            && navInstruction == nil && navDistance == nil && navSymbol == nil
            && navStreet == nil
    }
}

struct HeartRatePayload: Sendable {
    let bpm: Double
    let activeCalories: Double
    let timestamp: TimeInterval

    var dictionary: [String: Any] {
        [
            "type": "heartRate",
            "heartRate": bpm,
            "activeCalories": activeCalories,
            "timestamp": timestamp
        ]
    }
}
