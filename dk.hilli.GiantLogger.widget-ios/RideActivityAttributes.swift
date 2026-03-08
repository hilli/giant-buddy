import ActivityKit
import Foundation

struct RideActivityAttributes: ActivityAttributes {
    /// Dynamic state updated throughout the ride
    struct ContentState: Codable, Hashable {
        var speed: Double           // km/h
        var distance: Double        // km
        var elapsedSeconds: Int
        var batteryPercent: Int     // 0-100
        var avgSpeed: Double        // km/h
        var power: Double           // watts
    }
}
