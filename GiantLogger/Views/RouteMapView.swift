import SwiftUI
import MapKit
import Charts

struct RouteMapView: View {
    let route: Route

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
                startButton
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
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
            MapPolyline(coordinates: coordinates)
                .stroke(.blue, lineWidth: 3)

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
    .modelContainer(for: [Route.self, RouteWaypoint.self], inMemory: true)
}
