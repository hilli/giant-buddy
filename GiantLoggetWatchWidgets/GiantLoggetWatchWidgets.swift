import WidgetKit
import SwiftUI

// MARK: - Shared Entry & Provider

struct BikeEntry: TimelineEntry {
    let date: Date
    let batteryPercent: Int
    let estimatedRange: Int
    let lastConnected: Date?
}

struct BikeDataProvider: TimelineProvider {
    func placeholder(in context: Context) -> BikeEntry {
        BikeEntry(date: Date(), batteryPercent: 75, estimatedRange: 62, lastConnected: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BikeEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BikeEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [makeEntry()], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> BikeEntry {
        BikeEntry(
            date: Date(),
            batteryPercent: SharedBikeData.batteryPercent,
            estimatedRange: SharedBikeData.estimatedRange,
            lastConnected: SharedBikeData.lastConnected
        )
    }
}

// MARK: - Battery Complication

struct BatteryComplication: Widget {
    let kind = "dk.hilli.GiantLogger.watch.battery"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BikeDataProvider()) { entry in
            BatteryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("E-Bike Battery")
        .description("Shows your e-bike's battery level.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct BatteryComplicationView: View {
    var entry: BikeEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    private var circularView: some View {
        Gauge(value: Double(entry.batteryPercent), in: 0...100) {
            Image(systemName: "bicycle")
        } currentValueLabel: {
            Text("\(entry.batteryPercent)")
                .font(.system(.body, design: .rounded).bold())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(batteryGradient)
    }

    private var rectangularView: some View {
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

    private var inlineView: some View {
        HStack {
            Image(systemName: "bicycle")
            Text("Battery: \(entry.batteryPercent)%")
        }
    }

    private var cornerView: some View {
        Text("\(entry.batteryPercent)")
            .font(.system(.title, design: .rounded).bold())
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: Double(entry.batteryPercent), in: 0...100) {
                    Text("Battery")
                } currentValueLabel: {
                    Text("\(entry.batteryPercent)%")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(batteryGradient)
            }
    }

    private var batteryGradient: Gradient {
        Gradient(colors: [.red, .orange, .yellow, .green])
    }
}

// MARK: - Range Complication

struct RangeComplication: Widget {
    let kind = "dk.hilli.GiantLogger.watch.range"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BikeDataProvider()) { entry in
            RangeComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("E-Bike Range")
        .description("Shows your e-bike's estimated range.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct RangeComplicationView: View {
    var entry: BikeEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 0) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("\(entry.estimatedRange)")
                .font(.system(.title3, design: .rounded).bold())
            Text("km")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
                Text("Range")
                    .font(.headline)
                Spacer()
                Text("\(entry.estimatedRange) km")
                    .font(.headline.bold())
            }
            HStack {
                Image(systemName: "battery.\(batteryIconSuffix)")
                    .foregroundStyle(batteryColor)
                Text("\(entry.batteryPercent)%")
                    .font(.caption)
                if let lastConnected = entry.lastConnected {
                    Spacer()
                    Text("\(lastConnected, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inlineView: some View {
        HStack {
            Image(systemName: "bolt.fill")
            Text("Range: \(entry.estimatedRange) km")
        }
    }

    private var cornerView: some View {
        Text("\(entry.estimatedRange)")
            .font(.system(.title, design: .rounded).bold())
            .widgetCurvesContent()
            .widgetLabel {
                Text("⚡ \(entry.estimatedRange) km range")
            }
    }

    private var batteryColor: Color {
        switch entry.batteryPercent {
        case 0..<20: return .red
        case 20..<40: return .orange
        default: return .green
        }
    }

    private var batteryIconSuffix: String {
        switch entry.batteryPercent {
        case 0..<13: return "0percent"
        case 13..<38: return "25percent"
        case 38..<63: return "50percent"
        case 63..<88: return "75percent"
        default: return "100percent"
        }
    }
}
