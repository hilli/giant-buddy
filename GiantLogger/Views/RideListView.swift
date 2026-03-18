import SwiftUI
import SwiftData

struct RideListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "bicycle",
                        description: Text("Connect to your Giant e-bike and start recording to see your rides here.")
                    )
                } else {
                    List {
                        ForEach(rides) { ride in
                            NavigationLink(destination: RideDetailView(ride: ride)) {
                                RideRowView(ride: ride)
                            }
                        }
                        .onDelete(perform: deleteRides)
                    }
                    .refreshable {
                        // @Query auto-updates from CloudKit; brief pause for visual feedback
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            .navigationTitle("Ride History")
        }
    }

    private func deleteRides(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rides[index])
        }
        try? modelContext.save()
    }
}

struct RideRowView: View {
    let ride: Ride

    /// Display name: ride.name if set, otherwise formatted date
    private var displayName: String {
        ride.name.isEmpty
            ? ride.startDate.formatted(date: .abbreviated, time: .omitted)
            : ride.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayName)
                    .font(.headline)
                Spacer()
                Text(ride.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !ride.name.isEmpty {
                Text(ride.startDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label(String(format: "%.1f km", ride.totalDistance), systemImage: "road.lanes")
                Label(formatDuration(ride.duration), systemImage: "timer")
                Label(String(format: "%.1f km/h", ride.avgSpeed), systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if ride.startBattery > 0 || ride.endBattery > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "battery.100")
                        .font(.caption2)
                    Text("\(ride.startBattery)% → \(ride.endBattery)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(format: "%dh %dm", h, m)
        }
        return String(format: "%dm", m)
    }
}
