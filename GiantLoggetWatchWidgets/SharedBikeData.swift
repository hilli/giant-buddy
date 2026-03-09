import Foundation

/// Shared data between the main app and widget extension via App Group UserDefaults.
struct SharedBikeData {
    static let appGroupID = "group.dk.hilli.GiantLogger"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // Battery
    static var batteryPercent: Int {
        get { sharedDefaults?.integer(forKey: "batteryPercent") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "batteryPercent") }
    }

    static var batteryHealth: Int {
        get { sharedDefaults?.integer(forKey: "batteryHealth") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "batteryHealth") }
    }

    static var lastConnected: Date? {
        get { sharedDefaults?.object(forKey: "lastConnected") as? Date }
        set { sharedDefaults?.set(newValue, forKey: "lastConnected") }
    }

    // Bike info
    static var bikeName: String {
        get { sharedDefaults?.string(forKey: "bikeName") ?? "Giant E-Bike" }
        set { sharedDefaults?.set(newValue, forKey: "bikeName") }
    }

    static var totalOdometer: Double {
        get { sharedDefaults?.double(forKey: "totalOdometer") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "totalOdometer") }
    }

    static var assistMode: String {
        get { sharedDefaults?.string(forKey: "assistMode") ?? "—" }
        set { sharedDefaults?.set(newValue, forKey: "assistMode") }
    }

    static var estimatedRange: Int {
        get { sharedDefaults?.integer(forKey: "estimatedRange") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "estimatedRange") }
    }

    // Last ride
    static var lastRideDate: Date? {
        get { sharedDefaults?.object(forKey: "lastRideDate") as? Date }
        set { sharedDefaults?.set(newValue, forKey: "lastRideDate") }
    }

    static var lastRideDistance: Double {
        get { sharedDefaults?.double(forKey: "lastRideDistance") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "lastRideDistance") }
    }

    static var lastRideDuration: TimeInterval {
        get { sharedDefaults?.double(forKey: "lastRideDuration") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "lastRideDuration") }
    }

    static var lastRideAvgSpeed: Double {
        get { sharedDefaults?.double(forKey: "lastRideAvgSpeed") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "lastRideAvgSpeed") }
    }

    static var lastRideElevationGain: Double {
        get { sharedDefaults?.double(forKey: "lastRideElevationGain") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "lastRideElevationGain") }
    }

    // Ride stats
    static var totalRides: Int {
        get { sharedDefaults?.integer(forKey: "totalRides") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "totalRides") }
    }

    static var totalDistance: Double {
        get { sharedDefaults?.double(forKey: "totalDistance") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "totalDistance") }
    }

    static var weeklyDistance: Double {
        get { sharedDefaults?.double(forKey: "weeklyDistance") ?? 0 }
        set { sharedDefaults?.set(newValue, forKey: "weeklyDistance") }
    }
}
