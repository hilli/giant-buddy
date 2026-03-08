import SwiftUI
import SwiftData
import Charts

struct BatteryHealthView: View {
    @Query(sort: \BatterySnapshot.date) private var snapshots: [BatterySnapshot]
    @EnvironmentObject var bikeService: GiantBikeService

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                currentStatusCard
                if snapshots.count >= 2 {
                    healthChart
                    capacityChart
                    cyclesChart
                } else {
                    ContentUnavailableView(
                        "Not Enough Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Connect to your bike periodically to build a battery health timeline.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Battery Health")
    }

    // MARK: - Current Status

    private var currentStatusCard: some View {
        VStack(spacing: 12) {
            if let latest = snapshots.last {
                HStack(spacing: 16) {
                    healthGauge(latest.healthPercent)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(latest.healthPercent)% Health", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(healthColor(latest.healthPercent))
                        Label("\(latest.capacityPercent)% Charge", systemImage: "battery.75")
                            .font(.subheadline)
                        Label(String(format: "%.1f Wh", latest.fullCapacityWh), systemImage: "bolt.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("\(latest.chargeCycles) cycles", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else if let info = bikeService.bikeInfo {
                HStack(spacing: 16) {
                    healthGauge(info.epLifePercent)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(info.epLifePercent)% Health", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(healthColor(info.epLifePercent))
                        Label("\(info.epCapacityPercent)% Charge", systemImage: "battery.75")
                            .font(.subheadline)
                        Label(String(format: "%.1f Wh", info.epLastFullCapacityWh), systemImage: "bolt.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("\(info.epChargeCycles) cycles", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                Text("No battery data available.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func healthGauge(_ percent: Int) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100.0)
                .stroke(healthColor(percent), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.title3.bold())
                .monospacedDigit()
        }
        .frame(width: 80, height: 80)
    }

    // MARK: - Health Chart

    private var healthChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Health Over Time")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Chart {
                ForEach(snapshots) { snap in
                    LineMark(
                        x: .value("Date", snap.date),
                        y: .value("Health %", snap.healthPercent)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                }
                RuleMark(y: .value("Good", 80))
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Good")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                RuleMark(y: .value("Warning", 60))
                    .foregroundStyle(.orange.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Warning")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
            }
            .frame(height: 180)
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Capacity Chart

    private var capacityChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Full Capacity Over Time")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Chart {
                ForEach(snapshots) { snap in
                    LineMark(
                        x: .value("Date", snap.date),
                        y: .value("Wh", snap.fullCapacityWh)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                }
            }
            .frame(height: 180)
            .chartYAxisLabel("Wh")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Cycles Chart

    private var cyclesChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Charge Cycles")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Chart {
                ForEach(snapshots) { snap in
                    LineMark(
                        x: .value("Date", snap.date),
                        y: .value("Cycles", snap.chargeCycles)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                }
            }
            .frame(height: 180)
            .chartYAxisLabel("Cycles")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func healthColor(_ percent: Int) -> Color {
        if percent > 80 { return .green }
        if percent > 60 { return .yellow }
        return .red
    }
}
