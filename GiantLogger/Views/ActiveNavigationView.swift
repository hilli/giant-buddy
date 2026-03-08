import SwiftUI
import MapKit
import CoreLocation

struct ActiveNavigationView: View {
    let route: Route

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var navigationEngine = NavigationEngine()

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var nearestIndex: Int = 0
    @State private var distanceRemaining: Double = 0  // km
    @State private var percentComplete: Double = 0
    @State private var showArrival = false
    @State private var voiceEnabled = true
    @State private var hapticEnabled = true

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
                if navigationEngine.directionsAvailable, navigationEngine.currentInstruction != nil {
                    navigationBanner
                }
                if !navigationEngine.directionsAvailable {
                    fallbackNoticeBanner
                }
                if navigationEngine.isRerouting {
                    reroutingBanner
                }
                if navigationEngine.isOffRoute {
                    offRouteBanner
                }
                statusBar
            }

            if showArrival {
                arrivalOverlay
            }
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End") {
                    navigationEngine.stop()
                    dismiss()
                }
                .foregroundStyle(.red)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        voiceEnabled.toggle()
                        navigationEngine.voiceGuidanceEnabled = voiceEnabled
                        if !voiceEnabled { navigationEngine.stopVoice() }
                    } label: {
                        Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    Button {
                        hapticEnabled.toggle()
                        navigationEngine.hapticFeedbackEnabled = hapticEnabled
                    } label: {
                        Image(systemName: hapticEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    }
                }
            }
        }
        .onAppear {
            locationManager.startTracking()
            updateNavigation()
            Task {
                await navigationEngine.calculateDirections(for: route, from: locationManager.currentLocation)
            }
        }
        .onDisappear {
            navigationEngine.stop()
            locationManager.stopTracking()
        }
        .onChange(of: locationManager.currentLocation) {
            updateNavigation()
        }
        .onChange(of: navigationEngine.hasArrived) {
            if navigationEngine.hasArrived {
                withAnimation(.spring()) { showArrival = true }
            }
        }
    }

    // MARK: - Navigation Banner

    private var navigationBanner: some View {
        guard let instruction = navigationEngine.currentInstruction else {
            return AnyView(EmptyView())
        }
        let isUpcoming = navigationEngine.distanceToNextManeuver < 100

        return AnyView(HStack(spacing: 16) {
            Image(systemName: instruction.maneuverType.sfSymbol)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.maneuverType.rawValue)
                    .font(.headline)
                if let street = instruction.streetName {
                    Text("onto \(street)")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(formattedManeuverDistance(navigationEngine.distanceToNextManeuver))
                .font(.title2.bold().monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isUpcoming ? Color.orange : Color.blue))
    }

    // MARK: - Fallback Notice

    private var fallbackNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
            Text("Turn-by-turn unavailable — using breadcrumb navigation")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Rerouting Banner

    private var reroutingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text("Rerouting…")
                .font(.subheadline.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.orange)
    }

    // MARK: - Arrival Overlay

    private var arrivalOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("You've Arrived!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    Text(route.name)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(route.formattedDistance)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button {
                    navigationEngine.stop()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)
            }
            .padding(30)
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
            Text("Off Route — \(Int(navigationEngine.offRouteDistance))m away")
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

        // Feed location to navigation engine for turn-by-turn
        navigationEngine.updateLocation(userCL)
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
        let p = MKMapPoint(point.coordinate)
        let a = MKMapPoint(segStart.coordinate)
        let b = MKMapPoint(segEnd.coordinate)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        if lengthSq == 0 { return point.distance(from: segStart) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq))
        let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
        return p.distance(to: proj)
    }

    private var formattedRemaining: String {
        if distanceRemaining < 1 {
            return String(format: "%.0f m", distanceRemaining * 1000)
        }
        return String(format: "%.1f km", distanceRemaining)
    }

    private func formattedManeuverDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

#Preview {
    let route = Route(name: "Preview Route")
    NavigationStack {
        ActiveNavigationView(route: route)
    }
    .modelContainer(for: [Route.self, RouteWaypoint.self], inMemory: true)
}
