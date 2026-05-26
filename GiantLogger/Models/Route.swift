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

    /// Key waypoints used for turn-by-turn navigation directions.
    /// Returns user-defined waypoints if available, otherwise samples the route shape
    /// so imported GPX/ride routes are not re-routed from only start to finish.
    var navigationWaypoints: [RouteWaypoint] {
        let keyWPs = sortedWaypoints.filter { $0.isKeyWaypoint }
        if keyWPs.count >= 2 { return keyWPs }
        let sorted = sortedWaypoints
        guard sorted.count >= 2 else { return sorted }
        return sampledNavigationWaypoints(from: sorted)
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

    private func sampledNavigationWaypoints(from waypoints: [RouteWaypoint]) -> [RouteWaypoint] {
        let maxWaypointCount = 10
        let targetLegDistance: CLLocationDistance = 2_000
        guard waypoints.count > maxWaypointCount else { return waypoints }

        let routeDistance = max(totalDistance * 1_000, Self.distance(of: waypoints))
        let targetCount = min(
            maxWaypointCount,
            max(2, Int(ceil(routeDistance / targetLegDistance)) + 1)
        )
        guard targetCount < waypoints.count else { return waypoints }

        let targetSpacing = routeDistance / Double(targetCount - 1)
        var selected: [RouteWaypoint] = [waypoints[0]]
        var traveled: CLLocationDistance = 0
        var nextTarget = targetSpacing

        for index in 1..<(waypoints.count - 1) {
            traveled += Self.distance(from: waypoints[index - 1], to: waypoints[index])
            if traveled >= nextTarget {
                selected.append(waypoints[index])
                nextTarget += targetSpacing
            }
        }

        if selected.last?.id != waypoints.last?.id, let last = waypoints.last {
            selected.append(last)
        }
        return selected
    }

    private static func distance(of waypoints: [RouteWaypoint]) -> CLLocationDistance {
        guard waypoints.count >= 2 else { return 0 }
        var distance: CLLocationDistance = 0
        for index in 1..<waypoints.count {
            distance += Self.distance(from: waypoints[index - 1], to: waypoints[index])
        }
        return distance
    }

    private static func distance(from start: RouteWaypoint, to end: RouteWaypoint) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
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

    /// True for user-defined navigation waypoints (e.g. tapped points in route editor).
    /// False for interpolated polyline coordinates used for display/elevation.
    var isKeyWaypoint: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
