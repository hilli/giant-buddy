import SwiftUI
import WidgetKit

struct BatteryEntry: TimelineEntry {
    let date: Date
    let batteryPercent: Int
    let bikeName: String
}

struct BatteryComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> BatteryEntry {
        BatteryEntry(date: .now, batteryPercent: 75, bikeName: "Giant E-Bike")
    }

    func getSnapshot(in _: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> BatteryEntry {
        let defaults = UserDefaults(suiteName: "group.dk.hilli.GiantLogger")
        let battery = defaults?.integer(forKey: "batteryPercent") ?? 0
        let name = defaults?.string(forKey: "bikeName") ?? "Giant E-Bike"
        return BatteryEntry(date: .now, batteryPercent: battery, bikeName: name)
    }
}

struct BatteryComplicationView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularGauge
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            circularGauge
        }
    }

    private var circularGauge: some View {
        Gauge(value: Double(entry.batteryPercent), in: 0 ... 100) {
            Image(systemName: "bicycle")
        } currentValueLabel: {
            Text("\(entry.batteryPercent)")
                .font(.system(.body, design: .rounded).bold())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeGradient)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "bicycle")
                    .font(.caption2)
                Text(entry.bikeName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            Gauge(value: Double(entry.batteryPercent), in: 0 ... 100) {
                EmptyView()
            } currentValueLabel: {
                Text("\(entry.batteryPercent)%")
                    .font(.system(.caption, design: .rounded).bold())
            }
            .gaugeStyle(.linearCapacity)
            .tint(gaugeGradient)
        }
    }

    private var inlineView: some View {
        HStack(spacing: 2) {
            Image(systemName: "bicycle")
            Text("\(entry.batteryPercent)% Battery")
        }
    }

    private var cornerView: some View {
        Text("\(entry.batteryPercent)")
            .font(.system(.title3, design: .rounded).bold())
            .widgetLabel {
                Gauge(value: Double(entry.batteryPercent), in: 0 ... 100) {
                    Text("Battery")
                }
                .gaugeStyle(.linearCapacity)
                .tint(gaugeGradient)
            }
    }

    private var gaugeGradient: Gradient {
        Gradient(colors: [.red, .yellow, .green])
    }
}

struct BatteryComplication: Widget {
    let kind = "dk.hilli.GiantLogger.BatteryComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryComplicationProvider()) { entry in
            BatteryComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Bike Battery")
        .description("Shows your e-bike battery level")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}
