import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var session: WatchSessionManager
    @State private var selectedTab = Self.initialTab

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                metricsTab.tag(0)
                navigationTab.tag(1)
                controlTab.tag(2)
                bikeInfoTab.tag(3)
            }
            .tabViewStyle(.verticalPage)
        }
    }

    /// Starting tab; overridable in debug builds with `-ScreenshotTab N` for screenshots.
    private static var initialTab: Int {
        #if DEBUG
            UserDefaults.standard.integer(forKey: "ScreenshotTab")
        #else
            0
        #endif
    }

    // MARK: - Metrics Tab

    private var metricsTab: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f", session.speed))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(session.isRecording ? .green : .primary)
            Text("km/h")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 20)

            HStack(spacing: 16) {
                metricItem(
                    icon: "battery.100",
                    value: "\(session.battery)%",
                    color: batteryColor
                )
                metricItem(
                    icon: "bolt.fill",
                    value: String(format: "%.0fW", session.watts),
                    color: .yellow
                )
            }

            HStack(spacing: 16) {
                metricItem(
                    icon: "road.lanes",
                    value: String(format: "%.1fkm", session.distance),
                    color: .blue
                )
                metricItem(
                    icon: "timer",
                    value: session.formattedDuration,
                    color: .orange
                )
            }

            if session.cadence > 0 {
                HStack(spacing: 16) {
                    metricItem(
                        icon: "arrow.triangle.2.circlepath",
                        value: String(format: "%.0f rpm", session.cadence),
                        color: .purple
                    )
                    Spacer()
                }
            }

            if session.heartRate > 0 {
                HStack(spacing: 16) {
                    metricItem(
                        icon: "heart.fill",
                        value: String(format: "%.0f bpm", session.heartRate),
                        color: .red
                    )
                    if session.activeCalories > 0 {
                        metricItem(
                            icon: "flame.fill",
                            value: String(format: "%.0f kcal", session.activeCalories),
                            color: .orange
                        )
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Navigation Tab

    private var navigationTab: some View {
        VStack(spacing: 8) {
            if session.isNavigating {
                Image(systemName: session.navSymbol)
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)

                Text(session.navInstruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if session.navDistance > 0 {
                    Text(formatDistance(session.navDistance))
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                }

                if let street = session.navStreet, !street.isEmpty {
                    Text(street)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "location.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No active navigation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Start a route on iPhone")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control Tab

    private var controlTab: some View {
        VStack(spacing: 12) {
            Text(session.bikeName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                if session.isRecording {
                    session.stopRecording()
                } else {
                    session.startRecording()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: session.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(session.isRecording ? .red : .green)
                    Text(session.isRecording ? "Stop" : "Record")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if !session.isPhoneReachable {
                Label("iPhone not reachable", systemImage: "iphone.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bike Info Tab

    private var bikeInfoTab: some View {
        VStack(spacing: 6) {
            Text(session.bikeName)
                .font(.headline)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 20)

            bikeInfoRow(icon: "battery.100", label: "Battery", value: "\(session.battery)%", color: batteryColor)
            bikeInfoRow(icon: "bolt.fill", label: "Range", value: "\(session.estimatedRange) km", color: .orange)
            bikeInfoRow(icon: "road.lanes", label: "Odometer", value: String(format: "%.0f km", session.totalOdometer), color: .blue)
            bikeInfoRow(icon: "clock", label: "Usage", value: "\(session.totalUsageHours) hrs", color: .purple)

            Spacer()

            if session.isPhoneReachable {
                Label("Connected", systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label("Disconnected", systemImage: "iphone.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bikeInfoRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .rounded).bold())
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func metricItem(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.caption, design: .rounded).bold())
        }
    }

    private var batteryColor: Color {
        if session.battery > 50 { return .green }
        if session.battery > 20 { return .yellow }
        return .red
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
