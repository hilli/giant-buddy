import WidgetKit
import SwiftUI

struct LastRideProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastRideEntry {
        LastRideEntry(date: Date(), rideDate: Date(), distance: 12.5, duration: 2700, avgSpeed: 22.3, elevationGain: 150)
    }

    func getSnapshot(in context: Context, completion: @escaping (LastRideEntry) -> Void) {
        let entry = LastRideEntry(
            date: Date(),
            rideDate: SharedBikeData.lastRideDate,
            distance: SharedBikeData.lastRideDistance,
            duration: SharedBikeData.lastRideDuration,
            avgSpeed: SharedBikeData.lastRideAvgSpeed,
            elevationGain: SharedBikeData.lastRideElevationGain
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastRideEntry>) -> Void) {
        let entry = LastRideEntry(
            date: Date(),
            rideDate: SharedBikeData.lastRideDate,
            distance: SharedBikeData.lastRideDistance,
            duration: SharedBikeData.lastRideDuration,
            avgSpeed: SharedBikeData.lastRideAvgSpeed,
            elevationGain: SharedBikeData.lastRideElevationGain
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct LastRideEntry: TimelineEntry {
    let date: Date
    let rideDate: Date?
    let distance: Double
    let duration: TimeInterval
    let avgSpeed: Double
    let elevationGain: Double
}

struct LastRideWidgetView: View {
    var entry: LastRideEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "figure.outdoor.cycle")
                    .foregroundStyle(.green)
                Text("Last Ride")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if entry.rideDate != nil {
                Text(String(format: "%.1f km", entry.distance))
                    .font(.title2.bold())

                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2)
                    Text(formatDuration(entry.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let rideDate = entry.rideDate {
                    Text("\(rideDate, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text("No rides yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "figure.outdoor.cycle")
                        .foregroundStyle(.green)
                    Text("Last Ride")
                        .font(.subheadline.bold())
                }

                if let rideDate = entry.rideDate {
                    Text("\(rideDate, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.rideDate != nil {
                HStack(spacing: 16) {
                    statColumn(value: String(format: "%.1f", entry.distance), unit: "km", icon: "point.topleft.down.to.point.bottomright.curvepath")
                    statColumn(value: formatDuration(entry.duration), unit: "time", icon: "timer")
                    statColumn(value: String(format: "%.1f", entry.avgSpeed), unit: "km/h", icon: "gauge.with.dots.needle.33percent")
                    statColumn(value: String(format: "%.0f", entry.elevationGain), unit: "m ↑", icon: "mountain.2")
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "figure.outdoor.cycle")
                Text("Last Ride")
                    .font(.headline)
            }
            if entry.rideDate != nil {
                HStack {
                    Text(String(format: "%.1f km", entry.distance))
                        .font(.body.bold())
                    Text("•")
                    Text(formatDuration(entry.duration))
                    Text("•")
                    Text(String(format: "Ø %.0f km/h", entry.avgSpeed))
                }
                .font(.caption)
            } else {
                Text("No rides recorded")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func statColumn(value: String, unit: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)min"
        } else {
            return "\(m) min"
        }
    }
}

struct LastRideWidget: Widget {
    let kind: String = "dk.hilli.GiantLogger.LastRideWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastRideProvider()) { entry in
            LastRideWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "giantlogger://lastride"))
        }
        .configurationDisplayName("Last Ride")
        .description("Shows a summary of your most recent e-bike ride.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
