import CoreLocation
import Foundation
import SwiftData

/// Debug-only demo data for App Store screenshots.
///
/// Launch with `-ScreenshotMode YES` (optionally `-ScreenshotTab N`) to use an
/// in-memory store seeded with sample rides/routes and fake live bike telemetry.
/// Compiled out of Release builds.
enum ScreenshotMode {
    static var isEnabled: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "ScreenshotMode")
        #else
            false
        #endif
    }

    static var initialTab: Int {
        isEnabled ? UserDefaults.standard.integer(forKey: "ScreenshotTab") : 0
    }

    @MainActor
    static func seed(
        bikeManager: BikeManager,
        bikeService: GiantBikeService,
        locationManager: LocationManager,
        rideRecorder: RideRecorder,
        modelContext: ModelContext
    ) {
        guard isEnabled else { return }

        UserDefaults.standard.set("DEMO-0000", forKey: "savedDeviceID")
        UserDefaults.standard.set(bikeName, forKey: "savedDeviceName")

        seedRides(in: modelContext)
        seedRoutes(in: modelContext)
        try? modelContext.save()

        // GiantBikeService resets GEV state on connection changes and after its
        // handshake timeout, so re-apply the live state a few times.
        Task { @MainActor in
            for delay in [0.4, 1.1, 5.0] {
                try? await Task.sleep(for: .seconds(delay))
                applyLiveState(
                    bikeManager: bikeManager,
                    bikeService: bikeService,
                    locationManager: locationManager,
                    rideRecorder: rideRecorder
                )
            }
        }
    }

    // MARK: - Live state

    private static let bikeName = "Trance X E+"
    private static let home = CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683)

    @MainActor
    private static func applyLiveState(
        bikeManager: BikeManager,
        bikeService: GiantBikeService,
        locationManager: LocationManager,
        rideRecorder: RideRecorder
    ) {
        bikeManager.connectedPeripheralName = bikeName
        bikeManager.connectionState = .connected
        bikeService.isGevConnected = true
        bikeService.isFetchingBikeInfo = false
        bikeService.rideData = demoRideData
        bikeService.factoryData = demoFactoryData
        bikeService.batteryData = demoBatteryData
        bikeService.bikeInfo = demoBikeInfo
        rideRecorder.heartRate = 142
        locationManager.currentLocation = CLLocation(
            coordinate: home, altitude: 14, horizontalAccuracy: 5,
            verticalAccuracy: 5, timestamp: .now
        )
    }

    private static var demoRideData: RideData {
        var range = RemainingRangeData()
        range.eco = 85
        range.tour = 72
        range.normal = 60
        range.power = 45
        range.climb = 52
        range.boost = 30
        range.smart = 58

        var data = RideData()
        data.speed = 24.8
        data.cadence = 78
        data.torque = 32
        data.watts = 180
        data.motorWatts = 210
        data.batteryPercent = 76
        data.distance = 18.4
        data.rideTime = 2650
        data.assistCurrent = 6.2
        data.lightMode = 1
        data.rangeData = range
        return data
    }

    private static var demoFactoryData: FactoryData {
        var data = FactoryData()
        data.speedLimitation = 250
        data.circumference = 2350
        return data
    }

    private static var demoBatteryData: BatteryData {
        var data = BatteryData()
        data.capacityPercent = 76
        data.lifePercent = 94
        data.lastFullCapacityWh = 480
        return data
    }

    private static var demoBikeInfo: BikeInfo {
        var usage = ModeUsageData()
        usage.eco = 18
        usage.tour = 22
        usage.normal = 31
        usage.climb = 9
        usage.power = 12
        usage.boost = 5
        usage.smart = 3

        var info = BikeInfo()
        info.odo = 2140
        info.totalUsageHours = 118
        info.rcFwVersion = "1.4.2"
        info.rcHwVersion = "2.0"
        info.motorFwVersion = "5.1.0"
        info.motorHwVersion = "3.0"
        info.epVersion = "2.3.1"
        info.epChargeCycles = 63
        info.epCapacityWh = 500
        info.epCapacityPercent = 76
        info.epLifePercent = 94
        info.epLastFullCapacityWh = 480
        info.modeUsage = usage
        info.lastUpdated = .now
        return info
    }

    // MARK: - Stored history

    private struct DemoRide {
        let name: String
        let daysAgo: Int
        let minutes: Int
        let avgSpeed: Double
        let heading: Double
        let startBattery: Int
    }

    private static let demoRides = [
        DemoRide(name: "Morning commute", daysAgo: 0, minutes: 28, avgSpeed: 23.5, heading: 40, startBattery: 100),
        DemoRide(name: "Dyrehaven loop", daysAgo: 2, minutes: 74, avgSpeed: 21.0, heading: 0, startBattery: 95),
        DemoRide(name: "Amager Fælled gravel", daysAgo: 4, minutes: 52, avgSpeed: 19.2, heading: 170, startBattery: 88),
        DemoRide(name: "Coastal ride to Dragør", daysAgo: 7, minutes: 63, avgSpeed: 22.4, heading: 140,
                 startBattery: 100),
        DemoRide(name: "Evening spin", daysAgo: 9, minutes: 35, avgSpeed: 20.6, heading: 260, startBattery: 82)
    ]

    @MainActor
    private static func seedRides(in context: ModelContext) {
        let calendar = Calendar.current
        for demo in demoRides {
            let day = calendar.date(byAdding: .day, value: -demo.daysAgo, to: .now) ?? .now
            let start = calendar.date(bySettingHour: 7 + demo.daysAgo % 3 * 4, minute: 15, second: 0, of: day) ?? day
            let ride = Ride(startDate: start)
            ride.name = demo.name
            context.insert(ride)
            addSamples(to: ride, demo: demo, context: context)
            ride.computeSummary()
        }
    }

    @MainActor
    private static func addSamples(to ride: Ride, demo: DemoRide, context: ModelContext) {
        let interval = 2.0
        let count = demo.minutes * 30
        let headingRad = demo.heading * .pi / 180
        var distanceKm = 0.0
        var lat = home.latitude
        var lon = home.longitude

        for index in 0 ..< count {
            let progress = Double(index) / Double(count)
            let wave = sin(Double(index) / 40)
            let speed = max(0, demo.avgSpeed + wave * 4 + sin(Double(index) / 7) * 1.5)
            let stepKm = speed * interval / 3600
            distanceKm += stepKm
            // Curve the track so the map shows a loop-ish shape rather than a straight line.
            let bearing = headingRad + sin(progress * .pi * 2) * 1.2
            lat += stepKm / 111.0 * cos(bearing)
            lon += stepKm / (111.0 * cos(lat * .pi / 180)) * sin(bearing)

            let sample = RideSample(timestamp: ride.startDate.addingTimeInterval(Double(index) * interval))
            sample.speed = speed
            sample.cadence = speed > 1 ? 72 + wave * 10 : 0
            sample.torque = 28 + wave * 8
            sample.watts = 160 + wave * 40
            sample.motorWatts = 190 + wave * 50
            sample.batteryPercent = demo.startBattery - Int(progress * Double(demo.minutes) / 3)
            sample.distance = distanceKm
            sample.rideTime = Int(Double(index) * interval)
            sample.assistCurrent = 5.5 + wave
            sample.latitude = lat
            sample.longitude = lon
            sample.altitude = 12 + sin(progress * .pi * 3) * 18 + progress * 10
            sample.heartRate = 128 + wave * 14
            sample.gpsSpeed = speed / 3.6
            sample.horizontalAccuracy = 5
            sample.ride = ride
            context.insert(sample)
        }
    }

    private struct DemoRoute {
        let name: String
        let riddenDaysAgo: Int?
        let points: [(Double, Double)]
    }

    @MainActor
    private static func seedRoutes(in context: ModelContext) {
        let routes = [
            DemoRoute(name: "Copenhagen Harbour Circuit", riddenDaysAgo: 3, points: [
                (55.6761, 12.5683), (55.6795, 12.5900), (55.6880, 12.5990),
                (55.6925, 12.6000), (55.6830, 12.6050), (55.6700, 12.5900),
                (55.6640, 12.5770), (55.6761, 12.5683)
            ]),
            DemoRoute(name: "North Coast to Helsingør", riddenDaysAgo: nil, points: [
                (55.7300, 12.5800), (55.7900, 12.5900), (55.8600, 12.5600),
                (55.9300, 12.5200), (56.0000, 12.5600), (56.0360, 12.6130)
            ])
        ]

        for (offset, spec) in routes.enumerated() {
            let route = Route(name: spec.name)
            route.createdDate = Calendar.current.date(byAdding: .day, value: -(14 + offset * 5), to: .now) ?? .now
            if let daysAgo = spec.riddenDaysAgo {
                route.lastRiddenDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)
            }
            context.insert(route)
            for (index, point) in spec.points.enumerated() {
                let waypoint = RouteWaypoint(
                    index: index, latitude: point.0, longitude: point.1,
                    altitude: 10 + Double(index % 3) * 12
                )
                waypoint.isKeyWaypoint = true
                waypoint.route = route
                context.insert(waypoint)
            }
            route.recalculateStats()
        }
    }
}
