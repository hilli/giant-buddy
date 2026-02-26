import SwiftUI
import MapKit

struct DashboardView: View {
    @EnvironmentObject var bikeService: GiantBikeService
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var rideRecorder: RideRecorder

    var body: some View {
        NavigationStack {
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

                    // Mini map
                    miniMapSection

                    // Record button
                    recordButton

                    // Bike controls
                    if bikeService.isGevConnected {
                        bikeControlsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Giant Logger")
            .navigationBarTitleDisplayMode(.inline)
        }
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
        }
    }

    private var batteryRangeRow: some View {
        HStack(spacing: 12) {
            // Battery
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
                    Text(formatDuration(bikeService.rideData.rideTime))
                        .font(.callout.bold())
                        .monospacedDigit()
                }
                HStack {
                    Image(systemName: "fuelpump.fill")
                        .foregroundStyle(.mint)
                    Text("\(bikeService.rideData.range) km range")
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
            Map {
                UserAnnotation()
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
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

    private var bikeControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bike Controls")
                .font(.headline)

            HStack(spacing: 12) {
                ControlButton(title: "Light", icon: "lightbulb.fill") {
                    bikeService.toggleLight()
                }
                ControlButton(title: "Assist −", icon: "minus.circle.fill") {
                    bikeService.assistDown()
                }
                ControlButton(title: "Assist +", icon: "plus.circle.fill") {
                    bikeService.assistUp()
                }
                ControlButton(title: "Power", icon: "power") {
                    bikeService.togglePower()
                }
            }
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

struct ControlButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
