import SwiftUI
import SwiftData
import MapKit
import Charts

struct RouteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var routeName: String = ""
    @State private var waypoints: [EditableWaypoint] = []
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var calculatedLegs: [MKRoute] = []
    @State private var isCalculating = false
    @State private var showSaveSheet = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var calculationTask: Task<Void, Never>?

    // MARK: - EditableWaypoint

    struct EditableWaypoint: Identifiable, Equatable {
        let id = UUID()
        var coordinate: CLLocationCoordinate2D
        var name: String?

        static func == (lhs: EditableWaypoint, rhs: EditableWaypoint) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapSection
                controlButtons
                if !waypoints.isEmpty {
                    statsPreview
                    waypointList
                }
            }
        }
        .navigationTitle("Create Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { showSaveSheet = true }
                    .disabled(waypoints.count < 2)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    waypoints.reverse()
                    recalculateRoute()
                } label: {
                    Label("Reverse Route", systemImage: "arrow.uturn.backward")
                }
                .disabled(waypoints.count < 2)
            }
        }
        .alert("Save Route", isPresented: $showSaveSheet) {
            TextField("Route name", text: $routeName)
            Button("Save") { saveRoute() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for your route.")
        }
        .alert("Route Calculation", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Could not calculate cycling directions for this route.")
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Route polylines from calculated legs
                ForEach(Array(calculatedLegs.enumerated()), id: \.offset) { _, leg in
                    MapPolyline(leg.polyline)
                        .stroke(.blue, lineWidth: 4)
                }

                // Fallback: straight lines when no calculated route
                if calculatedLegs.isEmpty && waypoints.count >= 2 {
                    MapPolyline(coordinates: waypoints.map(\.coordinate))
                        .stroke(.blue.opacity(0.5), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                }

                // Numbered waypoint markers
                ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, waypoint in
                    Annotation("", coordinate: waypoint.coordinate) {
                        ZStack {
                            Circle()
                                .fill(markerColor(for: index))
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .onTapGesture { position in
                if let coordinate = proxy.convert(position, from: .local) {
                    addWaypoint(at: coordinate)
                }
            }
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            Group {
                if isCalculating {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            },
            alignment: .topTrailing
        )
        .overlay(
            Group {
                if waypoints.isEmpty {
                    Text("Tap on the map to add waypoints")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            },
            alignment: .bottom
        )
        .padding(.horizontal)
    }

    private func markerColor(for index: Int) -> Color {
        if index == 0 { return .green }
        if index == waypoints.count - 1 && waypoints.count > 1 { return .red }
        return .blue
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 12) {
            Button {
                if !waypoints.isEmpty {
                    waypoints.removeLast()
                    recalculateRoute()
                }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(waypoints.isEmpty)

            Button(role: .destructive) {
                waypoints.removeAll()
                calculatedLegs.removeAll()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(waypoints.isEmpty)

            Spacer()

            if waypoints.count >= 2 {
                Button {
                    recalculateRoute()
                } label: {
                    Label("Recalculate", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isCalculating)
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    // MARK: - Stats Preview

    private var statsPreview: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.blue)
                Text(formattedTotalDistance)
                    .font(.headline)
                Text("Distance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Image(systemName: "mountain.2")
                    .foregroundStyle(.blue)
                Text(formattedElevation)
                    .font(.headline)
                Text("Est. Elevation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.blue)
                Text("\(waypoints.count)")
                    .font(.headline)
                Text("Waypoints")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var formattedTotalDistance: String {
        let distanceKm = totalRouteDistance / 1000.0
        if distanceKm < 1 {
            return String(format: "%.0f m", totalRouteDistance)
        }
        return String(format: "%.1f km", distanceKm)
    }

    private var totalRouteDistance: Double {
        if !calculatedLegs.isEmpty {
            return calculatedLegs.reduce(0) { $0 + $1.distance }
        }
        // Fallback: straight-line distances
        guard waypoints.count >= 2 else { return 0 }
        var dist: Double = 0
        for i in 1..<waypoints.count {
            let prev = CLLocation(latitude: waypoints[i - 1].coordinate.latitude,
                                  longitude: waypoints[i - 1].coordinate.longitude)
            let curr = CLLocation(latitude: waypoints[i].coordinate.latitude,
                                  longitude: waypoints[i].coordinate.longitude)
            dist += curr.distance(from: prev)
        }
        return dist
    }

    private var formattedElevation: String {
        if !calculatedLegs.isEmpty {
            let totalAscent = calculatedLegs.compactMap(\.expectedTravelTime).reduce(0, +)
            // MKRoute doesn't expose elevation; use "—" when no data
            return "—"
        }
        return "—"
    }

    // MARK: - Waypoint List

    private var waypointList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Waypoints")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, waypoint in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(markerColor(for: index))
                            .frame(width: 24, height: 24)
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if let name = waypoint.name, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                        }
                        Text(formatCoordinate(waypoint.coordinate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        waypoints.remove(at: index)
                        recalculateRoute()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if index < waypoints.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.vertical)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func formatCoordinate(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
    }

    // MARK: - Actions

    private func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        let wp = EditableWaypoint(coordinate: coordinate)
        waypoints.append(wp)
        recalculateRoute()
    }

    private func recalculateRoute() {
        calculationTask?.cancel()
        guard waypoints.count >= 2 else {
            calculatedLegs.removeAll()
            return
        }

        isCalculating = true
        let currentWaypoints = waypoints

        calculationTask = Task {
            // Debounce — wait briefly in case more taps arrive
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            var legs: [MKRoute] = []
            var failed = false

            for i in 0..<(currentWaypoints.count - 1) {
                guard !Task.isCancelled else { return }
                let source = MKMapItem(placemark: MKPlacemark(coordinate: currentWaypoints[i].coordinate))
                let destination = MKMapItem(placemark: MKPlacemark(coordinate: currentWaypoints[i + 1].coordinate))

                let request = MKDirections.Request()
                request.source = source
                request.destination = destination
                request.transportType = .walking // .cycling unavailable in many regions
                request.requestsAlternateRoutes = false

                let directions = MKDirections(request: request)
                do {
                    let response = try await directions.calculate()
                    if let route = response.routes.first {
                        legs.append(route)
                    }
                } catch {
                    failed = true
                    break
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                isCalculating = false
                if failed {
                    calculatedLegs.removeAll()
                    errorMessage = "Could not calculate directions between some waypoints. The route will be saved with straight-line segments."
                    showError = true
                } else {
                    calculatedLegs = legs
                }
            }
        }
    }

    // MARK: - Save

    private func saveRoute() {
        let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = Route(name: name.isEmpty ? "Untitled Route" : name, source: "manual")

        if !calculatedLegs.isEmpty {
            // Use detailed polyline points from all legs
            var allPoints: [(CLLocationCoordinate2D)] = []
            for leg in calculatedLegs {
                let polyline = leg.polyline
                let count = polyline.pointCount
                let coords = UnsafeMutablePointer<CLLocationCoordinate2D>.allocate(capacity: count)
                defer { coords.deallocate() }
                polyline.getCoordinates(coords, range: NSRange(location: 0, length: count))

                let legCoords = Array(UnsafeBufferPointer(start: coords, count: count))
                // Skip the first point of subsequent legs to avoid duplicates at joins
                if allPoints.isEmpty {
                    allPoints.append(contentsOf: legCoords)
                } else {
                    allPoints.append(contentsOf: legCoords.dropFirst())
                }
            }

            for (idx, coord) in allPoints.enumerated() {
                let wp = RouteWaypoint(index: idx, latitude: coord.latitude, longitude: coord.longitude)
                route.waypoints?.append(wp)
            }
        } else {
            // Fallback: use tapped waypoints directly
            for (idx, wp) in waypoints.enumerated() {
                let rwp = RouteWaypoint(index: idx, latitude: wp.coordinate.latitude, longitude: wp.coordinate.longitude)
                route.waypoints?.append(rwp)
            }
        }

        route.recalculateStats()
        modelContext.insert(route)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RouteEditorView()
    }
    .modelContainer(for: [Route.self, RouteWaypoint.self], inMemory: true)
}
