import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @StateObject private var viewModel = TrendsViewModel()
    @State private var selectedPeriod: TrendsViewModel.TimePeriod = .month

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "chart.bar",
                        description: Text("Complete some rides to see your analytics and trends here.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            periodPicker
                            summarySection
                            trendsSection
                            recordsSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Analytics")
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(TrendsViewModel.TimePeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary Cards

    private var summarySection: some View {
        let summary = viewModel.computeSummary(rides: rides, period: selectedPeriod)
        let filteredCount = viewModel.filterRides(rides, for: selectedPeriod).count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.title2.bold())

            if filteredCount == 0 {
                Text("No rides in this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    StatCard(title: "Total Rides", value: "\(summary.rideCount)", icon: "bicycle")
                    StatCard(title: "Total Distance", value: String(format: "%.1f km", summary.totalDistance), icon: "road.lanes")
                    StatCard(title: "Total Duration", value: formatDuration(summary.totalDuration), icon: "timer")
                    StatCard(title: "Avg Speed", value: String(format: "%.1f km/h", summary.avgSpeed), icon: "speedometer")
                    StatCard(title: "Total Elevation", value: formatElevation(summary.totalElevation), icon: "mountain.2")
                    StatCard(title: "Battery Used", value: "\(summary.batteryUsed)%", icon: "battery.75")
                    StatCard(title: "Avg Efficiency", value: summary.avgEfficiency > 0 ? String(format: "%.2f km/%%", summary.avgEfficiency) : "—", icon: "leaf")
                    StatCard(title: "Longest Ride", value: String(format: "%.1f km", summary.longestRide), icon: "trophy")
                }
            }
        }
    }

    // MARK: - Trend Charts

    private var trendsSection: some View {
        let aggregates = viewModel.computeAggregates(rides: rides, period: selectedPeriod)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Trends")
                .font(.title2.bold())

            if aggregates.isEmpty {
                Text("Not enough data for trends.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                distanceChart(aggregates)
                speedChart(aggregates)
                powerChart(aggregates)
                efficiencyChart(aggregates)
            }
        }
    }

    private func distanceChart(_ data: [TrendsViewModel.DailyAggregate]) -> some View {
        let avg = data.reduce(0.0) { $0 + $1.totalDistance } / Double(data.count)

        return VStack(alignment: .leading, spacing: 4) {
            Text("Distance")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: chartUnit),
                        y: .value("km", item.totalDistance)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(String(format: "avg %.1f", avg))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
            }
            .frame(height: 180)
            .chartYAxisLabel("km")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func speedChart(_ data: [TrendsViewModel.DailyAggregate]) -> some View {
        let avg = data.reduce(0.0) { $0 + $1.avgSpeed } / Double(data.count)

        return VStack(alignment: .leading, spacing: 4) {
            Text("Average Speed")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Chart {
                ForEach(data) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: chartUnit),
                        y: .value("km/h", item.avgSpeed)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                }
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(String(format: "avg %.1f", avg))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
            }
            .frame(height: 180)
            .chartYAxisLabel("km/h")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func powerChart(_ data: [TrendsViewModel.DailyAggregate]) -> some View {
        let powerData = data.filter { $0.avgPower > 0 }
        guard !powerData.isEmpty else { return AnyView(EmptyView()) }

        let avg = powerData.reduce(0.0) { $0 + $1.avgPower } / Double(powerData.count)

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Average Power")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(powerData) { item in
                        LineMark(
                            x: .value("Date", item.date, unit: chartUnit),
                            y: .value("W", item.avgPower)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                        .symbol(Circle())
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(format: "avg %.0f", avg))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                }
                .frame(height: 180)
                .chartYAxisLabel("W")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    private func efficiencyChart(_ data: [TrendsViewModel.DailyAggregate]) -> some View {
        let effData = data.filter { $0.efficiency > 0 }
        guard !effData.isEmpty else { return AnyView(EmptyView()) }

        let avg = effData.reduce(0.0) { $0 + $1.efficiency } / Double(effData.count)

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Efficiency")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(effData) { item in
                        LineMark(
                            x: .value("Date", item.date, unit: chartUnit),
                            y: .value("km/%", item.efficiency)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                        .symbol(Circle())
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(.purple.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(format: "avg %.2f", avg))
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                }
                .frame(height: 180)
                .chartYAxisLabel("km/%")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - Personal Records

    private var recordsSection: some View {
        let records = viewModel.computeRecords(rides: rides)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records 🏆")
                .font(.title2.bold())

            if records.isEmpty {
                Text("Complete more rides to earn records.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(records) { record in
                        PersonalRecordRow(record: record)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var chartUnit: Calendar.Component {
        switch selectedPeriod {
        case .week: return .day
        case .month: return .weekOfYear
        case .allTime: return .month
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(format: "%dh %dm", h, m)
        }
        return String(format: "%dm", m)
    }

    private func formatElevation(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Personal Record Row

struct PersonalRecordRow: View {
    let record: TrendsViewModel.PersonalRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.icon)
                .font(.title3)
                .foregroundStyle(.yellow)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(record.value)
                    .font(.callout.bold())
                    .monospacedDigit()
            }

            Spacer()

            if let date = record.date {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    AnalyticsView()
        .modelContainer(for: Ride.self, inMemory: true)
}
