import ActivityKit
import SwiftUI
import WidgetKit

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f", context.state.speed))
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("km/h")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("\(context.state.batteryPercent)%", systemImage: batteryIcon(context.state.batteryPercent))
                            .font(.subheadline.bold())
                            .foregroundStyle(batteryColor(context.state.batteryPercent))
                        Text("\(Int(context.state.power))W")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(String(format: "%.1f km", context.state.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer()
                        Label(formatDuration(context.state.elapsedSeconds), systemImage: "timer")
                        Spacer()
                        Label(String(format: "Ø %.0f", context.state.avgSpeed), systemImage: "gauge.with.dots.needle.33percent")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "bicycle")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(String(format: "%.0f", context.state.speed))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "bicycle")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RideActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "bicycle")
                    .foregroundStyle(.green)
                Text("Giant Buddy")
                    .font(.subheadline.bold())
                Spacer()
                Label("\(context.state.batteryPercent)%", systemImage: batteryIcon(context.state.batteryPercent))
                    .font(.subheadline.bold())
                    .foregroundStyle(batteryColor(context.state.batteryPercent))
            }

            HStack(spacing: 16) {
                statItem(value: String(format: "%.1f", context.state.speed), unit: "km/h", icon: "gauge.with.dots.needle.67percent")
                statItem(value: "\(Int(context.state.power))", unit: "W", icon: "bolt.fill")
                statItem(value: String(format: "%.1f", context.state.distance), unit: "km", icon: "point.topleft.down.to.point.bottomright.curvepath")
            }

            HStack(spacing: 16) {
                statItem(value: formatDuration(context.state.elapsedSeconds), unit: "time", icon: "timer")
                statItem(value: String(format: "Ø %.1f", context.state.avgSpeed), unit: "km/h", icon: "gauge.with.dots.needle.33percent")
            }
        }
        .padding()
    }

    @ViewBuilder
    private func statItem(value: String, unit: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.bold())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func batteryColor(_ percent: Int) -> Color {
        switch percent {
        case 0..<20: return .red
        case 20..<40: return .orange
        default: return .green
        }
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case 0..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
