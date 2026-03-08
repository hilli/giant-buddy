import SwiftUI
import MapKit
import CoreLocation

struct ActiveNavigationView: View {
    let route: Route

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var nearestIndex: Int = 0
    @State private var distanceRemaining: Double = 0  // km
    @State private var percentComplete: Double = 0
    @State private var isOffRoute = false
    @State private var offRouteDistance: Double = 0    // meters

    private let offRouteThreshold: Double = 100 // meters

    private var sortedWaypoints: [RouteWaypoint] {
        route.sortedWaypoints
    }

    private var allCoordinates: [CLLocationCoordinate2D] {
        route.coordinates
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapView

            VStack(spacing: 0) {
                if isOffRoute {
                    offRouteBanner
                }
                statusBar
            }
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End") {
                    dismiss()
                }
                .foregroundStyle(.red)
            }
        }
        .onAppear {
            locationManager.startTracking()
            updateNavigation()
        }
        .onDisappear {
            locationManager.stopTracking()
        }
        .onChange(of: locationManager.currentLocation) {
            updateNavigation()
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $cameraPosition) {
            // Completed portion (dimmed)
            if nearestIndex > 0 {
                let completedCoords = Array(allCoordinates.prefix(nearestIndex + 1))
                MapPolyline(coordinates: completedCoords)
                    .stroke(.gray.opacity(0.4), lineWidth: 3)
            }

            // Upcoming portion (highlighted)
            if nearestIndex < allCoordinates.count {
                let upcomingCoords = Array(allCoordinates.suffix(from: nearestIndex))
                MapPolyline(coordinates: upcomingCoords)
                    .stroke(.blue, lineWidth: 5)
            }

            // Start marker
            if let start = allCoordinates.first {
                Annotation("Start", coordinate: start) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }

            // End marker
            if let end = allCoordinates.last, allCoordinates.count > 1 {
                Annotation("Finish", coordinate: end) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }

            // User location is shown automatically by MapKit
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formattedRemaining)
                    .font(.title3.bold())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Progress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", percentComplete))
                    .font(.title3.bold())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(route.formattedDistance)
                    .font(.title3.bold())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Off-Route Banner

    private var offRouteBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Off Route — \(Int(offRouteDistance))m away")
                .font(.subheadline.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.red)
    }

    // MARK: - Navigation Logic

    private func updateNavigation() {
        guard let userLocation = locationManager.currentLocation else { return }
        let waypoints = sortedWaypoints
        guard waypoints.count >= 2 else { return }

        let userCL = CLLocation(
            latitude: userLocation.coordinate.latitude,
            longitude: userLocation.coordinate.longitude
        )

        // Find nearest waypoint
        var minDist = Double.greatestFiniteMagnitude
        var closestIdx = 0

        for (idx, waypoint) in waypoints.enumerated() {
            let wpLoc = CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude)
            let dist = userCL.distance(from: wpLoc)
            if dist < minDist {
                minDist = dist
                closestIdx = idx
            }
        }

        nearestIndex = closestIdx

        // Off-route detection using minimum distance to any segment
        let segmentDist = minimumDistanceToRoute(from: userCL, coordinates: waypoints)
        offRouteDistance = segmentDist
        isOffRoute = segmentDist > offRouteThreshold

        // Calculate remaining distance from nearest point to end
        var remaining: Double = 0
        for idx in closestIdx..<(waypoints.count - 1) {
            let segStart = CLLocation(latitude: waypoints[idx].latitude, longitude: waypoints[idx].longitude)
            let segEnd = CLLocation(latitude: waypoints[idx + 1].latitude, longitude: waypoints[idx + 1].longitude)
            remaining += segEnd.distance(from: segStart)
        }
        distanceRemaining = remaining / 1000.0

        // Calculate percent complete
        let total = route.totalDistance
        if total > 0 {
            percentComplete = max(0, min(100, ((total - distanceRemaining) / total) * 100))
        } else {
            percentComplete = 0
        }
    }

    /// Minimum perpendicular distance from a point to the nearest route segment
    private func minimumDistanceToRoute(from location: CLLocation, coordinates: [RouteWaypoint]) -> Double {
        guard coordinates.count >= 2 else {
            if let first = coordinates.first {
                return location.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
            }
            return Double.greatestFiniteMagnitude
        }

        var minDist = Double.greatestFiniteMagnitude

        for idx in 0..<(coordinates.count - 1) {
            let segStart = CLLocation(latitude: coordinates[idx].latitude, longitude: coordinates[idx].longitude)
            let segEnd = CLLocation(latitude: coordinates[idx + 1].latitude, longitude: coordinates[idx + 1].longitude)
            let dist = distanceFromPointToSegment(point: location, segStart: segStart, segEnd: segEnd)
            minDist = min(minDist, dist)
        }

        return minDist
    }

    /// Distance from a point to a line segment defined by two CLLocations
    private func distanceFromPointToSegment(point: CLLocation, segStart: CLLocation, segEnd: CLLocation) -> Double {
        let deltaX = segEnd.coordinate.longitude - segStart.coordinate.longitude
        let deltaY = segEnd.coordinate.latitude - segStart.coordinate.latitude

        if deltaX == 0 && deltaY == 0 {
            return point.distance(from: segStart)
        }

        // Project point onto the segment using parametric form
        let param = max(0, min(1,
            ((point.coordinate.longitude - segStart.coordinate.longitude) * deltaX +
             (point.coordinate.latitude - segStart.coordinate.latitude) * deltaY) /
            (deltaX * deltaX + deltaY * deltaY)
        ))

        let projLat = segStart.coordinate.latitude + param * deltaY
        let projLon = segStart.coordinate.longitude + param * deltaX
        let projected = CLLocation(latitude: projLat, longitude: projLon)

        return point.distance(from: projected)
    }

    private var formattedRemaining: String {
        if distanceRemaining < 1 {
            return String(format: "%.0f m", distanceRemaining * 1000)
        }
        return String(format: "%.1f km", distanceRemaining)
    }
}

#Preview {
    let route = Route(name: "Preview Route")
    NavigationStack {
        ActiveNavigationView(route: route)
    }
    .modelContainer(for: [Route.self, RouteWaypoint.self], inMemory: true)
}
