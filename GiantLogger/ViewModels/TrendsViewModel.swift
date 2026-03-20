import Foundation

@MainActor
class TrendsViewModel: ObservableObject {

    enum TimePeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case allTime = "All Time"
    }

    struct PeriodSummary {
        let rideCount: Int
        let totalDistance: Double
        let totalDuration: Int
        let avgSpeed: Double
        let totalElevation: Double
        let batteryUsedWh: Double
        let avgEfficiency: Double
        let longestRide: Double
    }

    struct DailyAggregate: Identifiable {
        let id = UUID()
        let date: Date
        let totalDistance: Double
        let avgSpeed: Double
        let avgPower: Double
        let efficiency: Double
        let rideCount: Int
    }

    struct PersonalRecord: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let date: Date?
        let icon: String
    }

    // MARK: - Filtering

    func filterRides(_ rides: [Ride], for period: TimePeriod) -> [Ride] {
        let now = Date.now
        switch period {
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            return rides.filter { $0.startDate >= cutoff }
        case .month:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            return rides.filter { $0.startDate >= cutoff }
        case .allTime:
            return rides
        }
    }

    // MARK: - Summary

    func computeSummary(rides: [Ride], period: TimePeriod) -> PeriodSummary {
        let filtered = filterRides(rides, for: period)

        let rideCount = filtered.count
        let totalDistance = filtered.reduce(0.0) { $0 + $1.totalDistance }
        let totalDuration = filtered.reduce(0) { $0 + $1.duration }
        let avgSpeed = filtered.isEmpty ? 0 : filtered.reduce(0.0) { $0 + $1.avgSpeed } / Double(filtered.count)
        let totalElevation = filtered.reduce(0.0) { $0 + $1.elevationGain }
        let batteryUsedWh = filtered.reduce(0.0) { $0 + Self.rideEnergyWh($1) }
        let avgEfficiency = batteryUsedWh > 0 ? totalDistance / (batteryUsedWh / 1000.0) : 0
        let longestRide = filtered.map(\.totalDistance).max() ?? 0

        return PeriodSummary(
            rideCount: rideCount,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            avgSpeed: avgSpeed,
            totalElevation: totalElevation,
            batteryUsedWh: batteryUsedWh,
            avgEfficiency: avgEfficiency,
            longestRide: longestRide
        )
    }

    // MARK: - Aggregates

    func computeAggregates(rides: [Ride], period: TimePeriod) -> [DailyAggregate] {
        let filtered = filterRides(rides, for: period)
        guard !filtered.isEmpty else { return [] }

        let calendar = Calendar.current
        let grouped: [Date: [Ride]]

        switch period {
        case .week:
            grouped = Dictionary(grouping: filtered) { ride in
                calendar.startOfDay(for: ride.startDate)
            }
        case .month:
            grouped = Dictionary(grouping: filtered) { ride in
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ride.startDate)
                return calendar.date(from: components) ?? ride.startDate
            }
        case .allTime:
            grouped = Dictionary(grouping: filtered) { ride in
                let components = calendar.dateComponents([.year, .month], from: ride.startDate)
                return calendar.date(from: components) ?? ride.startDate
            }
        }

        return grouped.map { date, groupRides in
            let totalDist = groupRides.reduce(0.0) { $0 + $1.totalDistance }
            let avgSpd = groupRides.reduce(0.0) { $0 + $1.avgSpeed } / Double(groupRides.count)
            let avgPwr = groupRides.reduce(0.0) { $0 + $1.avgPower } / Double(groupRides.count)
            let groupWh = groupRides.reduce(0.0) { $0 + Self.rideEnergyWh($1) }
            let eff = groupWh > 0 ? totalDist / (groupWh / 1000.0) : 0

            return DailyAggregate(
                date: date,
                totalDistance: totalDist,
                avgSpeed: avgSpd,
                avgPower: avgPwr,
                efficiency: eff,
                rideCount: groupRides.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Personal Records

    func computeRecords(rides: [Ride]) -> [PersonalRecord] {
        guard !rides.isEmpty else { return [] }

        var records: [PersonalRecord] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        if let longest = rides.max(by: { $0.totalDistance < $1.totalDistance }) {
            records.append(PersonalRecord(
                title: "Longest Ride",
                value: String(format: "%.1f km", longest.totalDistance),
                date: longest.startDate,
                icon: "road.lanes"
            ))
        }

        if let fastest = rides.max(by: { $0.avgSpeed < $1.avgSpeed }), fastest.avgSpeed > 0 {
            records.append(PersonalRecord(
                title: "Fastest Ride",
                value: String(format: "%.1f km/h", fastest.avgSpeed),
                date: fastest.startDate,
                icon: "speedometer"
            ))
        }

        if let mostElevation = rides.max(by: { $0.elevationGain < $1.elevationGain }), mostElevation.elevationGain > 0 {
            records.append(PersonalRecord(
                title: "Most Elevation",
                value: String(format: "%.0f m", mostElevation.elevationGain),
                date: mostElevation.startDate,
                icon: "mountain.2"
            ))
        }

        if let highestPower = rides.max(by: { $0.avgPower < $1.avgPower }), highestPower.avgPower > 0 {
            records.append(PersonalRecord(
                title: "Highest Power",
                value: String(format: "%.0f W", highestPower.avgPower),
                date: highestPower.startDate,
                icon: "bolt"
            ))
        }

        // Best efficiency: highest km per kWh of motor energy
        let ridesWithEnergy = rides.filter { Self.rideEnergyWh($0) > 0 }
        if let bestEfficiency = ridesWithEnergy.max(by: {
            $0.totalDistance / Self.rideEnergyWh($0) <
            $1.totalDistance / Self.rideEnergyWh($1)
        }) {
            let whUsed = Self.rideEnergyWh(bestEfficiency)
            let kmPerKwh = bestEfficiency.totalDistance / (whUsed / 1000.0)
            records.append(PersonalRecord(
                title: "Best Efficiency",
                value: String(format: "%.1f km/kWh", kmPerKwh),
                date: bestEfficiency.startDate,
                icon: "leaf"
            ))
        }

        // Most rides in a day
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: rides) { calendar.startOfDay(for: $0.startDate) }
        if let busiestDay = byDay.max(by: { $0.value.count < $1.value.count }), busiestDay.value.count > 1 {
            records.append(PersonalRecord(
                title: "Most Rides in a Day",
                value: "\(busiestDay.value.count) rides",
                date: busiestDay.key,
                icon: "repeat"
            ))
        }

        return records
    }

    // MARK: - Energy Calculation

    /// Compute motor energy used during a ride in watt-hours.
    /// Integrates motorWatts × sample interval across all samples.
    static func rideEnergyWh(_ ride: Ride) -> Double {
        let sorted = (ride.samples ?? [])
            .filter { $0.motorWatts > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else {
            // Fallback: avgPower × duration
            return ride.avgPower * Double(ride.duration) / 3600.0
        }
        var totalWs = 0.0
        for idx in 1..<sorted.count {
            let deltaSeconds = sorted[idx].timestamp
                .timeIntervalSince(sorted[idx - 1].timestamp)
            guard deltaSeconds > 0, deltaSeconds < 60 else { continue }
            let avgWatts = (sorted[idx].motorWatts + sorted[idx - 1].motorWatts) / 2.0
            totalWs += avgWatts * deltaSeconds
        }
        return totalWs / 3600.0
    }
}
