import Foundation
import SwiftData
import CoreLocation

// MARK: - Route

@Model
final class Route {
    var id: UUID = UUID()
    var name: String = ""
    var createdDate: Date = Date.now
    var lastRiddenDate: Date?
    var source: String = "gpx_import" // "gpx_import", "ride_conversion", "manual"
    var totalDistance: Double = 0     // km
    var elevationGain: Double = 0    // meters
    var maxAltitude: Double = 0      // meters
    var minAltitude: Double = 0      // meters

    @Relationship(deleteRule: .cascade, inverse: \RouteWaypoint.route)
    var waypoints: [RouteWaypoint]? = []

    init() {}

    init(name: String, source: String = "gpx_import") {
        self.name = name
        self.source = source
    }

    // MARK: Computed Properties

    var sortedWaypoints: [RouteWaypoint] {
        (waypoints ?? []).sorted { $0.index < $1.index }
    }

    var coordinates: [CLLocationCoordinate2D] {
        sortedWaypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var startCoordinate: CLLocationCoordinate2D? {
        sortedWaypoints.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var endCoordinate: CLLocationCoordinate2D? {
        sortedWaypoints.last.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var formattedDistance: String {
        if totalDistance < 1 {
            return String(format: "%.0f m", totalDistance * 1000)
        }
        return String(format: "%.1f km", totalDistance)
    }

    /// Recalculate distance and elevation stats from waypoints
    func recalculateStats() {
        let sorted = sortedWaypoints
        guard sorted.count >= 2 else {
            totalDistance = 0
            elevationGain = 0
            maxAltitude = sorted.first?.altitude ?? 0
            minAltitude = sorted.first?.altitude ?? 0
            return
        }

        var distance: Double = 0
        var gain: Double = 0
        var maxAlt = sorted[0].altitude
        var minAlt = sorted[0].altitude

        for idx in 1..<sorted.count {
            let prev = CLLocation(latitude: sorted[idx - 1].latitude, longitude: sorted[idx - 1].longitude)
            let curr = CLLocation(latitude: sorted[idx].latitude, longitude: sorted[idx].longitude)
            distance += curr.distance(from: prev)

            let elevDiff = sorted[idx].altitude - sorted[idx - 1].altitude
            if elevDiff > 0 {
                gain += elevDiff
            }
            maxAlt = max(maxAlt, sorted[idx].altitude)
            minAlt = min(minAlt, sorted[idx].altitude)
        }

        totalDistance = distance / 1000.0 // meters to km
        elevationGain = gain
        maxAltitude = maxAlt
        minAltitude = minAlt
    }
}

// MARK: - RouteWaypoint

@Model
final class RouteWaypoint {
    var id: UUID = UUID()
    var route: Route?
    var index: Int = 0
    var latitude: Double = 0
    var longitude: Double = 0
    var altitude: Double = 0
    var name: String?
    var timestamp: Date?

    init() {}

    init(
        index: Int, latitude: Double, longitude: Double,
        altitude: Double = 0, name: String? = nil, timestamp: Date? = nil
    ) {
        self.index = index
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.name = name
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
