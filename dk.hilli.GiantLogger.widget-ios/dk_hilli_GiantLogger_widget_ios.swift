import WidgetKit
import SwiftUI

// MARK: - Battery Widget

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), batteryPercent: 75, batteryHealth: 95, bikeName: "Giant E-Bike", lastConnected: Date(), estimatedRange: 62, totalOdometer: 1234)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let entry = BatteryEntry(
            date: Date(),
            batteryPercent: SharedBikeData.batteryPercent,
            batteryHealth: SharedBikeData.batteryHealth,
            bikeName: SharedBikeData.bikeName,
            lastConnected: SharedBikeData.lastConnected,
            estimatedRange: SharedBikeData.estimatedRange,
            totalOdometer: SharedBikeData.totalOdometer
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let entry = BatteryEntry(
            date: Date(),
            batteryPercent: SharedBikeData.batteryPercent,
            batteryHealth: SharedBikeData.batteryHealth,
            bikeName: SharedBikeData.bikeName,
            lastConnected: SharedBikeData.lastConnected,
            estimatedRange: SharedBikeData.estimatedRange,
            totalOdometer: SharedBikeData.totalOdometer
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let batteryPercent: Int
    let batteryHealth: Int
    let bikeName: String
    let lastConnected: Date?
    let estimatedRange: Int
    let totalOdometer: Double
}

struct BatteryWidgetView: View {
    var entry: BatteryEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallBatteryView
        case .systemMedium:
            mediumBatteryView
        case .accessoryCircular:
            circularBatteryView
        case .accessoryRectangular:
            rectangularBatteryView
        case .accessoryInline:
            inlineBatteryView
        default:
            smallBatteryView
        }
    }

    // MARK: - Home Screen Small
    private var smallBatteryView: some View {
        VStack(spacing: 8) {
            Image(systemName: batteryIcon)
                .font(.system(size: 36))
                .foregroundStyle(batteryColor)

            Text("\(entry.batteryPercent)%")
                .font(.title.bold())
                .foregroundStyle(batteryColor)

            if entry.estimatedRange > 0 {
                Label("\(entry.estimatedRange) km", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let lastConnected = entry.lastConnected {
                Text("\(lastConnected, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Not connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Home Screen Medium
    private var mediumBatteryView: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 40))
                    .foregroundStyle(batteryColor)
                Text("\(entry.batteryPercent)%")
                    .font(.title2.bold())
                    .foregroundStyle(batteryColor)
            }
            .frame(width: 80)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.green)
                    Text(entry.bikeName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Label("\(entry.batteryHealth)%", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                    if entry.estimatedRange > 0 {
                        Label("\(entry.estimatedRange) km", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if entry.totalOdometer > 0 {
                        Label(String(format: "%.0f km", entry.totalOdometer), systemImage: "road.lanes")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if let lastConnected = entry.lastConnected {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                        Text("\(lastConnected, style: .relative) ago")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Lock Screen Circular
    private var circularBatteryView: some View {
        Gauge(value: Double(entry.batteryPercent), in: 0...100) {
            Image(systemName: "bicycle")
        } currentValueLabel: {
            Text("\(entry.batteryPercent)")
                .font(.system(.body, design: .rounded).bold())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(batteryGradient)
    }

    // MARK: - Lock Screen Rectangular
    private var rectangularBatteryView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "bicycle")
                Text("Battery")
                    .font(.headline)
                Spacer()
                Text("\(entry.batteryPercent)%")
                    .font(.headline.bold())
            }
            Gauge(value: Double(entry.batteryPercent), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(batteryGradient)
        }
    }

    // MARK: - Lock Screen Inline
    private var inlineBatteryView: some View {
        HStack {
            Image(systemName: "bicycle")
            Text("Battery: \(entry.batteryPercent)%")
        }
    }

    // MARK: - Helpers
    private var batteryColor: Color {
        switch entry.batteryPercent {
        case 0..<20: return .red
        case 20..<40: return .orange
        default: return .green
        }
    }

    private var batteryGradient: Gradient {
        Gradient(colors: [.red, .orange, .yellow, .green])
    }

    private var batteryIcon: String {
        switch entry.batteryPercent {
        case 0..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct BatteryWidget: Widget {
    let kind: String = "dk.hilli.GiantLogger.BatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("E-Bike Battery")
        .description("Shows your e-bike's current battery level and health.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
