import SwiftUI
import MapKit
import WeatherKit

struct DashboardView: View {
    @EnvironmentObject var bikeService: GiantBikeService
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var rideRecorder: RideRecorder
    @EnvironmentObject var weatherManager: WeatherManager
    @EnvironmentObject var navigationEngine: NavigationEngine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var mapCameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSearch = false

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    /// Build trail coordinates from current ride samples.
    private var trailCoordinates: [CLLocationCoordinate2D] {
        guard let samples = rideRecorder.currentRide?.samples else { return [] }
        return samples
            .sorted { $0.timestamp < $1.timestamp }
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        NavigationStack {
            if isLandscape {
                landscapeDashboard
                    .navigationTitle("Giant Buddy")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Connection status bar
                        connectionStatusBar

                        // Big speed display
                        speedSection

                        // Primary metrics grid
                        primaryMetricsGrid

                        // Battery & range row
                        batteryRangeRow

                        // Weather
                        weatherSection

                        // Mini map
                        miniMapSection

                        // Record button
                        recordButton
                    }
                    .padding()
                }
                .refreshable {
                    if bikeService.isGevConnected {
                        // Already connected — refresh telemetry
                        bikeService.fetchAllBikeData()
                        try? await Task.sleep(for: .seconds(7))
                    } else if bikeManager.connectionState == .disconnected {
                        // Not connected — scan and auto-connect
                        bikeManager.startScan()
                        // Wait up to 10s for a device to be discovered and connected
                        for _ in 0..<100 {
                            try? await Task.sleep(for: .milliseconds(100))
                            if bikeManager.connectionState == .connected || bikeService.isGevConnected {
                                break
                            }
                            // Auto-connect to the first discovered Giant bike
                            if bikeManager.connectionState == .scanning,
                               let first = bikeManager.discoveredDevices.first {
                                bikeManager.connect(to: first.peripheral)
                            }
                        }
                    }
                }
                .navigationTitle("Giant Buddy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToRideTab)) { _ in
            showSearch = false
        }
        .task(id: locationManager.currentLocation) {
            if let location = locationManager.currentLocation {
                await weatherManager.fetchWeather(for: location)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if navigationEngine.activeRoute != nil, let loc = newLocation {
                navigationEngine.updateLocation(loc)
            }
        }
        .onAppear {
            if locationManager.currentLocation == nil {
                locationManager.requestSingleLocation()
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Landscape Layout

    private var landscapeDashboard: some View {
        VStack(spacing: 8) {
            // Minimal status bar
            compactStatusBar
                .padding(.horizontal)

            HStack(spacing: 16) {
                // Left side: Speed + Record button
                VStack(spacing: 12) {
                    Spacer()
                    landscapeSpeedSection
                    recordButton
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right side: Metrics, Map, Controls
                VStack(spacing: 8) {
                    compactMetricsRow
                    compactBatteryInfo
                    compactWeatherRow
                    if locationManager.currentLocation != nil {
                        compactMiniMap
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var compactStatusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Spacer()
            if bikeService.isGevConnected {
                lightStatusIcon
            }
            if rideRecorder.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("REC • \(rideRecorder.sampleCount)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var landscapeSpeedSection: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", bikeService.rideData.speed))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("km/h")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var compactMetricsRow: some View {
        HStack(spacing: 8) {
            CompactMetricCard(
                value: String(format: "%.0f", bikeService.rideData.watts),
                unit: "W",
                icon: "bolt.fill",
                color: .orange
            )
            CompactMetricCard(
                value: String(format: "%.0f", bikeService.rideData.cadence),
                unit: "rpm",
                icon: "arrow.clockwise",
                color: .blue
            )
            CompactMetricCard(
                value: String(format: "%.1f", bikeService.rideData.torque),
                unit: "Nm",
                icon: "gearshape.fill",
                color: .purple
            )
            CompactMetricCard(
                value: String(format: "%.1f", bikeService.rideData.assistCurrent),
                unit: "A",
                icon: "bolt.car.fill",
                color: .cyan
            )
        }
    }

    private var compactBatteryInfo: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                compactBatteryIcon
                Text("\(bikeService.rideData.batteryPercent)%")
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Image(systemName: "road.lanes")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(String(format: "%.1f km", bikeService.rideData.distance))
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                Text(formatDuration(rideRecorder.isRecording ? rideRecorder.elapsedSeconds : bikeService.rideData.rideTime))
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Image(systemName: "fuelpump.fill")
                    .font(.caption2)
                    .foregroundStyle(.mint)
                Text("\(bikeService.rideData.range) km")
                    .font(.caption.bold())
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var compactBatteryIcon: some View {
        let pct = bikeService.rideData.batteryPercent
        let name = pct > 75 ? "battery.100" : pct > 50 ? "battery.75" : pct > 25 ? "battery.50" : "battery.25"
        let color: Color = pct > 20 ? .green : pct > 10 ? .orange : .red
        return Image(systemName: name)
            .font(.caption)
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    private var compactMiniMap: some View {
        Map(position: $mapCameraPosition) {
            UserAnnotation()
            if trailCoordinates.count >= 2 {
                MapPolyline(coordinates: trailCoordinates)
                    .stroke(.blue, lineWidth: 2)
            }
            if navigationEngine.activeRoute != nil {
                let routeCoords = navigationEngine.navigationRouteCoordinates
                if routeCoords.count >= 2 {
                    MapPolyline(coordinates: routeCoords)
                        .stroke(.red, lineWidth: 3)
                }
            }
        }
        .frame(maxHeight: navigationEngine.activeRoute != nil ? 120 : 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    // MARK: - Components

    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if bikeService.isGevConnected {
                lightStatusIcon
            }
            if rideRecorder.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("REC • \(rideRecorder.sampleCount) samples")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var speedSection: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f", bikeService.rideData.speed))
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("km/h")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var primaryMetricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            MetricCard(
                title: "Power",
                value: String(format: "%.0f", bikeService.rideData.watts),
                unit: "W",
                icon: "bolt.fill",
                color: .orange
            )
            MetricCard(
                title: "Cadence",
                value: String(format: "%.0f", bikeService.rideData.cadence),
                unit: "rpm",
                icon: "arrow.clockwise",
                color: .blue
            )
            MetricCard(
                title: "Torque",
                value: String(format: "%.1f", bikeService.rideData.torque),
                unit: "Nm",
                icon: "gearshape.fill",
                color: .purple
            )
            MetricCard(
                title: "Current",
                value: String(format: "%.1f", bikeService.rideData.assistCurrent),
                unit: "A",
                icon: "bolt.car.fill",
                color: .cyan
            )
        }
    }

    private var batteryRangeRow: some View {
        HStack(spacing: 12) {
            // Battery + Range
            HStack {
                batteryIcon
                VStack(alignment: .leading) {
                    Text("\(bikeService.rideData.batteryPercent)%")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(bikeService.rideData.range) km")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("Range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Distance & Time
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "road.lanes")
                        .foregroundStyle(.green)
                    Text(String(format: "%.1f km", bikeService.rideData.distance))
                        .font(.callout.bold())
                        .monospacedDigit()
                }
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.cyan)
                    Text(formatDuration(rideRecorder.isRecording ? rideRecorder.elapsedSeconds : bikeService.rideData.rideTime))
                        .font(.callout.bold())
                        .monospacedDigit()
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var miniMapSection: some View {
        if locationManager.currentLocation != nil {
            VStack(spacing: 8) {
                // Navigation instruction card
                if navigationEngine.activeRoute != nil {
                    navigationCard
                }

                Map(position: $mapCameraPosition) {
                    UserAnnotation()
                    // Past ride trail in blue
                    if trailCoordinates.count >= 2 {
                        MapPolyline(coordinates: trailCoordinates)
                            .stroke(.blue, lineWidth: 3)
                    }
                    // Upcoming route in red
                    if navigationEngine.activeRoute != nil {
                        let routeCoords = navigationEngine.navigationRouteCoordinates
                        if routeCoords.count >= 2 {
                            MapPolyline(coordinates: routeCoords)
                                .stroke(.red, lineWidth: 4)
                        }
                        if let start = routeCoords.first {
                            Annotation("Start", coordinate: start) {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        if let end = routeCoords.last, routeCoords.count > 1 {
                            Annotation("Finish", coordinate: end) {
                                Image(systemName: "flag.checkered")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(height: navigationEngine.activeRoute != nil ? 300 : 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(navigationEngine.activeRoute != nil)
                .mapControls {
                    if navigationEngine.activeRoute != nil {
                        MapUserLocationButton()
                        MapCompass()
                    }
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            rideRecorder.toggleRecording()
        } label: {
            HStack {
                Image(systemName: rideRecorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title2)
                Text(rideRecorder.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(rideRecorder.isRecording ? Color.red : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Navigation Card

    @ViewBuilder
    private var navigationCard: some View {
        VStack(spacing: 6) {
            if let instruction = navigationEngine.currentInstruction {
                HStack(spacing: 16) {
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
                    Text(formattedDistance(navigationEngine.distanceToNextManeuver))
                        .font(.title2.bold().monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(navigationEngine.distanceToNextManeuver < 100 ? Color.orange : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if navigationEngine.isRerouting {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Rerouting…").font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if navigationEngine.isOffRoute {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Off Route — \(Int(navigationEngine.offRouteDistance))m away")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Navigation controls
            HStack {
                Button {
                    navigationEngine.voiceGuidanceEnabled.toggle()
                    if !navigationEngine.voiceGuidanceEnabled { navigationEngine.stopVoice() }
                } label: {
                    Image(systemName: navigationEngine.voiceGuidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }

                Button {
                    navigationEngine.hapticFeedbackEnabled.toggle()
                } label: {
                    Image(systemName: navigationEngine.hapticFeedbackEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                }

                Spacer()

                Button("End Navigation") {
                    navigationEngine.stop()
                }
                .foregroundStyle(.red)
                .font(.subheadline.bold())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return "\(Int(meters)) m"
        }
    }

    // MARK: - Weather

    @ViewBuilder
    private var weatherSection: some View {
        if let current = weatherManager.currentWeather {
            HStack(spacing: 16) {
                // Current conditions
                HStack(spacing: 8) {
                    Image(systemName: current.symbolName)
                        .font(.largeTitle)
                        .symbolRenderingMode(.multicolor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.temperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
                            .font(.title.bold())
                        Text(current.condition.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Next 3 hours
                HStack(spacing: 16) {
                    ForEach(weatherManager.hourlyForecast, id: \.date) { hour in
                        VStack(spacing: 4) {
                            Text(hour.date.formatted(.dateTime.hour()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: hour.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.title3)
                            Text(hour.temperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
                                .font(.callout.bold())
                        }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var compactWeatherRow: some View {
        if let current = weatherManager.currentWeather {
            HStack(spacing: 8) {
                Image(systemName: current.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
                Text(current.temperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
                    .font(.caption.bold())

                Divider().frame(height: 16)

                ForEach(weatherManager.hourlyForecast, id: \.date) { hour in
                    HStack(spacing: 2) {
                        Image(systemName: hour.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.caption2)
                        Text(hour.temperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
                            .font(.caption2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private var batteryIcon: some View {
        let pct = bikeService.rideData.batteryPercent
        let name = pct > 75 ? "battery.100" : pct > 50 ? "battery.75" : pct > 25 ? "battery.50" : "battery.25"
        let color: Color = pct > 20 ? .green : pct > 10 ? .orange : .red
        return Image(systemName: name)
            .font(.title)
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
    }

    private var lightStatusIcon: some View {
        let mode = bikeService.rideData.lightMode
        let icon: String
        let color: Color
        switch mode {
        case 1: icon = "lightbulb.fill"; color = .yellow
        case 2: icon = "lightbulb.min.fill"; color = .yellow.opacity(0.6)
        case 3: icon = "lightbulb.max.fill"; color = .yellow
        default: icon = "lightbulb.slash"; color = .gray
        }
        return Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var statusColor: Color {
        switch bikeManager.connectionState {
        case .connected: .green
        case .connecting, .discoveringServices: .orange
        case .scanning: .blue
        case .disconnected: .gray
        }
    }

    private var statusText: String {
        switch bikeManager.connectionState {
        case .connected: "Connected to \(bikeManager.connectedPeripheralName ?? "bike")"
        case .connecting: "Connecting…"
        case .discoveringServices: "Discovering services…"
        case .scanning: "Scanning…"
        case .disconnected: "Disconnected"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Subviews

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CompactMetricCard: View {
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
