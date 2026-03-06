import SwiftUI
import MapKit
import Charts

struct RideDetailView: View {
    let ride: Ride
    @EnvironmentObject var stravaService: StravaService
    @State private var exportURL: IdentifiableURL?
    @State private var stravaUploadSuccess = false

    private var sortedSamples: [RideSample] {
        (ride.samples ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var gpsCoordinates: [CLLocationCoordinate2D] {
        sortedSamples
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Map with track
                if !gpsCoordinates.isEmpty {
                    mapSection
                }

                // Summary stats
                summaryCards

                // Charts
                if sortedSamples.count > 1 {
                    speedChart
                    elevationChart
                    powerChart
                    batteryChart
                }
            }
            .padding()
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        exportAs(.csv)
                    } label: {
                        Label("Export CSV", systemImage: "doc.text")
                    }
                    Button {
                        exportAs(.gpx)
                    } label: {
                        Label("Export GPX", systemImage: "map")
                    }
                    if stravaService.isConnected {
                        Divider()
                        Button {
                            Task {
                                do {
                                    try await stravaService.uploadRide(ride)
                                    stravaUploadSuccess = true
                                } catch {
                                    stravaService.lastUploadError = error.localizedDescription
                                }
                            }
                        } label: {
                            if stravaService.isUploading {
                                Label("Uploading…", systemImage: "arrow.up.circle")
                            } else {
                                Label("Upload to Strava", systemImage: "arrow.up.circle.fill")
                            }
                        }
                        .disabled(stravaService.isUploading)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $exportURL) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Uploaded to Strava", isPresented: $stravaUploadSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your ride has been uploaded to Strava.")
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map {
            MapPolyline(coordinates: gpsCoordinates)
                .stroke(.blue, lineWidth: 3)

            if let first = gpsCoordinates.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "flag.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                }
            }
            if let last = gpsCoordinates.last, gpsCoordinates.count > 1 {
                Annotation("End", coordinate: last) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                }
            }
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Distance", value: String(format: "%.1f km", ride.totalDistance), icon: "road.lanes")
            StatCard(title: "Duration", value: formatDuration(ride.duration), icon: "timer")
            StatCard(title: "Avg Speed", value: String(format: "%.1f km/h", ride.avgSpeed), icon: "speedometer")
            StatCard(title: "Max Speed", value: String(format: "%.1f km/h", ride.maxSpeed), icon: "gauge.with.dots.needle.33percent")
            StatCard(title: "Avg Power", value: String(format: "%.0f W", ride.avgPower), icon: "bolt.fill")
            StatCard(title: "Max Power", value: String(format: "%.0f W", ride.maxPower), icon: "bolt.circle.fill")
            StatCard(title: "Avg Cadence", value: String(format: "%.0f rpm", ride.avgCadence), icon: "arrow.clockwise")
            StatCard(title: "Elevation", value: String(format: "↑ %.0f m", ride.elevationGain), icon: "mountain.2.fill")
            StatCard(title: "Battery", value: "\(ride.startBattery)% → \(ride.endBattery)%", icon: "battery.50")
        }
    }

    // MARK: - Charts

    private var speedChart: some View {
        VStack(alignment: .leading) {
            Text("Speed")
                .font(.headline)
            Chart(sortedSamples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("km/h", sample.speed)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 150)
            .chartYAxisLabel("km/h")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var powerChart: some View {
        VStack(alignment: .leading) {
            Text("Power")
                .font(.headline)
            Chart(sortedSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("W", sample.watts)
                )
                .foregroundStyle(.orange.opacity(0.3))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("W", sample.watts)
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 150)
            .chartYAxisLabel("Watts")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var elevationChart: some View {
        VStack(alignment: .leading) {
            Text("Elevation")
                .font(.headline)
            Chart(sortedSamples.filter { $0.altitude != 0 }) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("m", sample.altitude)
                )
                .foregroundStyle(.brown.opacity(0.3))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("m", sample.altitude)
                )
                .foregroundStyle(.brown)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 150)
            .chartYAxisLabel("m")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var batteryChart: some View {
        VStack(alignment: .leading) {
            Text("Battery")
                .font(.headline)
            Chart(sortedSamples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("%", sample.batteryPercent)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.monotone)
            }
            .frame(height: 120)
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Export

    private enum ExportFormat { case csv, gpx }

    private func exportAs(_ format: ExportFormat) {
        let dateStr = ride.startDate.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        var url: URL?
        switch format {
        case .csv:
            let content = ExportService.exportCSV(ride: ride)
            url = ExportService.writeToTempFile(content: content, filename: "ride_\(dateStr).csv")
        case .gpx:
            let content = ExportService.exportGPX(ride: ride)
            url = ExportService.writeToTempFile(content: content, filename: "ride_\(dateStr).gpx")
        }
        if let url {
            exportURL = IdentifiableURL(url: url)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.bold())
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
