import SwiftUI
import Charts

/// Battery prediction visualization for a route, designed to embed in RouteMapView.
struct RangePredictionView: View {
    let prediction: RangePredictor.RoutePrediction
    let routeDistance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Battery Prediction")
                .font(.headline)
                .padding(.horizontal)

            batteryChart
                .padding(.horizontal)

            summaryCard
                .padding(.horizontal)

            if !prediction.hasHistoricalData {
                limitedDataBanner
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Battery Chart

    private var batteryChart: some View {
        Chart(prediction.segments) { segment in
            AreaMark(
                x: .value("Distance (km)", segment.distance),
                y: .value("Battery (%)", segment.predictedBattery)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [batteryColor(for: segment.predictedBattery).opacity(0.4),
                             batteryColor(for: segment.predictedBattery).opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Distance (km)", segment.distance),
                y: .value("Battery (%)", segment.predictedBattery)
            )
            .foregroundStyle(batteryColor(for: segment.predictedBattery))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
        .chartXAxisLabel("km")
        .chartYAxis {
            AxisMarks(values: [0, 20, 50, 100]) { value in
                AxisGridLine(stroke: value.as(Int.self) == 20
                             ? StrokeStyle(lineWidth: 1, dash: [4, 4])
                             : StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(value.as(Int.self) == 20 ? .orange : .secondary.opacity(0.3))
                AxisValueLabel()
            }
        }
        .frame(height: 140)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: summaryIcon)
                .font(.title2)
                .foregroundStyle(summaryColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(summaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summaryColor)

                if let mode = prediction.recommendedMode {
                    Text("Switch to \(mode) to complete this route")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if prediction.canComplete {
                Text("\(Int(prediction.estimatedEndBattery))%")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(summaryColor)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Limited Data Banner

    private var limitedDataBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Limited data — prediction improves with more rides")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private var summaryText: String {
        if prediction.canComplete {
            return "Arrive with ~\(Int(prediction.estimatedEndBattery))% battery"
        } else if let depletionPoint = prediction.segments.last(where: { $0.predictedBattery > 0 }) {
            return "Battery depleted at \(String(format: "%.1f", depletionPoint.distance)) km"
        } else {
            return "Insufficient battery for this route"
        }
    }

    private var summaryIcon: String {
        prediction.canComplete ? "battery.100.bolt" : "battery.0"
    }

    private var summaryColor: Color {
        if !prediction.canComplete { return .red }
        if prediction.estimatedEndBattery < 10 { return .orange }
        if prediction.estimatedEndBattery < 20 { return .yellow }
        return .green
    }

    private func batteryColor(for battery: Double) -> Color {
        switch battery {
        case ..<10:  return .red
        case ..<20:  return .orange
        default:     return .green
        }
    }
}

#Preview {
    let segments = stride(from: 0.0, through: 50, by: 1.0).map { dist in
        let battery = max(100 - dist * 1.8, 0)
        return RangePredictor.PredictionSegment(
            distance: dist,
            altitude: 100 + sin(dist / 5) * 50,
            predictedBattery: battery,
            status: RangePredictor.SegmentStatus(battery: battery)
        )
    }
    let prediction = RangePredictor.RoutePrediction(
        segments: segments,
        canComplete: true,
        estimatedEndBattery: 10,
        recommendedMode: nil,
        hasHistoricalData: true
    )

    return RangePredictionView(prediction: prediction, routeDistance: 50)
        .padding()
}
