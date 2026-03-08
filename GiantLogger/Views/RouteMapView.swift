import SwiftUI
import SwiftData
import MapKit
import Charts

struct RouteMapView: View {
    let route: Route

    @EnvironmentObject var bikeService: GiantBikeService
    @Query(sort: \Ride.startDate) private var rides: [Ride]
    @StateObject private var rangePredictor = RangePredictor()

    @State private var prediction: RangePredictor.RoutePrediction?
    @State private var isNavigating = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var exportURL: RouteExportURL?

    private var sortedWaypoints: [RouteWaypoint] {
        route.sortedWaypoints
    }

    private var coordinates: [CLLocationCoordinate2D] {
        route.coordinates
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mapSection
                statsSection
                elevationProfileSection
                rangePredictionSection
                startButton
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            rangePredictor.learnFromRides(rides)
            let battery = bikeService.rideData.batteryPercent
            let currentBattery = battery > 0 ? battery : 100
            prediction = rangePredictor.predict(route: route, currentBattery: currentBattery)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportRouteAsGPX()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $exportURL) { item in
            RouteShareSheet(activityItems: [item.url])
        }
        .fullScreenCover(isPresented: $isNavigating) {
            NavigationStack {
                ActiveNavigationView(route: route)
            }
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            if let prediction, prediction.segments.count >= 2 {
                ForEach(coloredRouteSegments(prediction: prediction)) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, lineWidth: 3)
                }
            } else {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue, lineWidth: 3)
            }

            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                }
            }

            if let end = coordinates.last, coordinates.count > 1 {
                Annotation("End", coordinate: end) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.red)
                        .font(.title2)
                }
            }
        }
        .frame(height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    // MARK: - Stats

    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(icon: "arrow.left.and.right", title: "Distance", value: route.formattedDistance)
            StatTile(icon: "mountain.2", title: "Elevation Gain", value: String(format: "%.0f m", route.elevationGain))
            StatTile(icon: "mappin.and.ellipse", title: "Waypoints", value: "\(sortedWaypoints.count)")
            StatTile(icon: "arrow.up", title: "Max Altitude", value: String(format: "%.0f m", route.maxAltitude))
            StatTile(icon: "arrow.down", title: "Min Altitude", value: String(format: "%.0f m", route.minAltitude))
            StatTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Source", value: sourceLabel)
            if let prediction {
                StatTile(
                    icon: prediction.canComplete ? "battery.100.bolt" : "battery.0",
                    title: "Est. End Battery",
                    value: "\(Int(prediction.estimatedEndBattery))%"
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Elevation Profile

    private var elevationProfileSection: some View {
        VStack(alignment: .leading) {
            Text("Elevation Profile")
                .font(.headline)
                .padding(.horizontal)

            Chart(elevationData, id: \.distance) { point in
                AreaMark(
                    x: .value("Distance (km)", point.distance),
                    y: .value("Altitude (m)", point.altitude)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.brown.opacity(0.6), .brown.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Distance (km)", point.distance),
                    y: .value("Altitude (m)", point.altitude)
                )
                .foregroundStyle(.brown)
                .interpolationMethod(.catmullRom)
            }
            .chartYAxisLabel("m")
            .chartXAxisLabel("km")
            .frame(height: 150)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    // MARK: - Range Prediction

    private var rangePredictionSection: some View {
        Group {
            if let prediction {
                RangePredictionView(prediction: prediction, routeDistance: route.totalDistance)
            }
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            isNavigating = true
        } label: {
            Label("Start Navigation", systemImage: "location.north.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .padding()
    }

    // MARK: - Helpers

    private var sourceLabel: String {
        switch route.source {
        case "gpx_import": return "GPX"
        case "ride_conversion": return "Ride"
        case "manual": return "Manual"
        default: return route.source
        }
    }

    // MARK: - Colored Route Segments

    private struct ColoredSegment: Identifiable {
        let id = UUID()
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    private func coloredRouteSegments(prediction: RangePredictor.RoutePrediction) -> [ColoredSegment] {
        let waypoints = sortedWaypoints
        guard waypoints.count >= 2, prediction.segments.count == waypoints.count else {
            return [ColoredSegment(coordinates: coordinates, color: .blue)]
        }

        var segments: [ColoredSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = [waypoints[0].coordinate]
        var currentColor = colorForStatus(prediction.segments[0].status)

        for i in 1..<waypoints.count {
            let segColor = colorForStatus(prediction.segments[i].status)
            if segColor == currentColor {
                currentCoords.append(waypoints[i].coordinate)
            } else {
                // Bridge: include this point in both to avoid gaps
                currentCoords.append(waypoints[i].coordinate)
                segments.append(ColoredSegment(coordinates: currentCoords, color: currentColor))
                currentCoords = [waypoints[i].coordinate]
                currentColor = segColor
            }
        }

        if currentCoords.count >= 2 {
            segments.append(ColoredSegment(coordinates: currentCoords, color: currentColor))
        }

        return segments
    }

    private func colorForStatus(_ status: RangePredictor.SegmentStatus) -> Color {
        switch status {
        case .safe:     return .green
        case .warning:  return .yellow
        case .critical: return .red
        case .depleted: return .red.opacity(0.5)
        }
    }

    private struct ElevationPoint {
        let distance: Double // km
        let altitude: Double // m
    }

    private var elevationData: [ElevationPoint] {
        let sorted = sortedWaypoints
        guard sorted.count >= 2 else {
            return sorted.map { ElevationPoint(distance: 0, altitude: $0.altitude) }
        }

        var result: [ElevationPoint] = []
        var cumDist: Double = 0

        result.append(ElevationPoint(distance: 0, altitude: sorted[0].altitude))

        for idx in 1..<sorted.count {
            let prev = CLLocation(latitude: sorted[idx - 1].latitude, longitude: sorted[idx - 1].longitude)
            let curr = CLLocation(latitude: sorted[idx].latitude, longitude: sorted[idx].longitude)
            cumDist += curr.distance(from: prev) / 1000.0
            result.append(ElevationPoint(distance: cumDist, altitude: sorted[idx].altitude))
        }

        return result
    }

    private func exportRouteAsGPX() {
        let sorted = sortedWaypoints
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Giant Buddy"
          xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(route.name)</name>
            <trkseg>

        """

        for waypoint in sorted {
            gpx += "      <trkpt lat=\"\(waypoint.latitude)\" lon=\"\(waypoint.longitude)\">\n"
            gpx += "        <ele>\(waypoint.altitude)</ele>\n"
            if let time = waypoint.timestamp {
                gpx += "        <time>\(formatter.string(from: time))</time>\n"
            }
            if let name = waypoint.name {
                gpx += "        <name>\(name)</name>\n"
            }
            gpx += "      </trkpt>\n"
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(route.name).gpx")
        try? gpx.write(to: tempURL, atomically: true, encoding: .utf8)
        exportURL = RouteExportURL(url: tempURL)
    }
}

// MARK: - StatTile

private struct StatTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Reuse IdentifiableURL + ShareSheet from RideDetailView

/// Wrapper to make URL identifiable for sheet presentation
private struct RouteExportURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RouteShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let route = Route(name: "Sample Route")
    NavigationStack {
        RouteMapView(route: route)
    }
    .environmentObject(GiantBikeService())
    .modelContainer(for: [Route.self, RouteWaypoint.self, Ride.self, RideSample.self], inMemory: true)
}
