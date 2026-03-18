import Foundation
import SwiftData

@Model
final class Ride {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date = Date.now
    var endDate: Date?

    // Summary stats (computed on stop)
    var totalDistance: Double = 0      // km
    var duration: Int = 0             // seconds
    var avgSpeed: Double = 0          // km/h
    var maxSpeed: Double = 0          // km/h
    var avgPower: Double = 0          // W
    var maxPower: Double = 0          // W
    var avgCadence: Double = 0        // RPM
    var maxCadence: Double = 0        // RPM
    var elevationGain: Double = 0     // meters climbed
    var maxAltitude: Double = 0       // highest point (m)
    var minAltitude: Double = 0       // lowest point (m)
    var startBattery: Int = 0         // %
    var endBattery: Int = 0           // %

    @Relationship(deleteRule: .cascade, inverse: \RideSample.ride)
    var samples: [RideSample]? = []

    init(startDate: Date = .now) {
        self.id = UUID()
        self.startDate = startDate
    }

    func computeSummary() {
        let allSamples = samples ?? []
        guard !allSamples.isEmpty else { return }
        let sorted = allSamples.sorted { $0.timestamp < $1.timestamp }

        endDate = sorted.last?.timestamp
        duration = Int((endDate ?? startDate).timeIntervalSince(startDate))
        // Use GPS-accumulated distance from last sample
        totalDistance = sorted.last?.distance ?? 0

        let movingSamples = sorted.filter { $0.speed > 0.5 }
        avgSpeed = movingSamples.isEmpty ? 0 : movingSamples.map(\.speed).reduce(0, +) / Double(movingSamples.count)
        maxSpeed = sorted.map(\.speed).max() ?? 0

        let powerSamples = sorted.filter { $0.motorWatts > 0 }
        avgPower = powerSamples.isEmpty ? 0 : powerSamples.map(\.motorWatts).reduce(0, +) / Double(powerSamples.count)
        maxPower = sorted.map(\.motorWatts).max() ?? 0

        let cadenceSamples = sorted.filter { $0.cadence > 0 }
        avgCadence = cadenceSamples.isEmpty ? 0 : cadenceSamples.map(\.cadence).reduce(0, +) / Double(cadenceSamples.count)
        maxCadence = sorted.map(\.cadence).max() ?? 0

        startBattery = sorted.first?.batteryPercent ?? 0
        endBattery = sorted.last?.batteryPercent ?? 0

        // Elevation gain: sum of positive altitude changes (uphill only)
        let validAltitudes = sorted.map(\.altitude).filter { $0 != 0 }
        if !validAltitudes.isEmpty {
            maxAltitude = validAltitudes.max() ?? 0
            minAltitude = validAltitudes.min() ?? 0
            var gain = 0.0
            for i in 1..<validAltitudes.count {
                let diff = validAltitudes[i] - validAltitudes[i-1]
                if diff > 0 { gain += diff }
            }
            elevationGain = gain
        }
    }
}

@Model
final class RideSample {
    var timestamp: Date = Date.now
    var ride: Ride?

    // Bike telemetry
    var speed: Double = 0            // km/h
    var cadence: Double = 0          // RPM
    var torque: Double = 0           // Nm
    var watts: Double = 0            // W (bike native from 0x1B)
    var motorWatts: Double = 0       // W (calculated: assistCurrent × estimated voltage)
    var batteryPercent: Int = 0      // 0-100
    var distance: Double = 0         // km
    var rideTime: Int = 0            // seconds
    var range: Int = 0               // km
    var errorCode: Int = 0
    var assistCurrent: Double = 0    // Amps from motor
    var lightMode: Int = 0           // 0=OFF, 1=ON, 2=LOW, 3=HIGH
    var packetLog: String = ""       // Timestamped TX/RX hex packets since last sample

    // GPS data (iOS-only bonus)
    var latitude: Double = 0
    var longitude: Double = 0
    var altitude: Double = 0         // meters
    var heartRate: Double = 0        // BPM from Apple Watch
    var gpsSpeed: Double = 0         // m/s
    var course: Double = 0           // degrees

    init(timestamp: Date = .now) {
        self.timestamp = timestamp
    }

    convenience init(rideData: RideData, latitude: Double = 0, longitude: Double = 0, altitude: Double = 0, gpsSpeed: Double = 0, course: Double = 0) {
        self.init(timestamp: .now)
        self.speed = rideData.speed
        self.cadence = rideData.cadence
        self.torque = rideData.torque
        self.watts = rideData.watts
        self.motorWatts = rideData.motorWatts
        self.batteryPercent = rideData.batteryPercent
        self.distance = rideData.distance
        self.rideTime = rideData.rideTime
        self.range = rideData.range
        self.errorCode = rideData.errorCode
        self.assistCurrent = rideData.assistCurrent
        self.lightMode = rideData.lightMode
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.gpsSpeed = gpsSpeed
        self.course = course
    }
}
