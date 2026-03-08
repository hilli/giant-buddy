import SwiftUI
import Charts
import CoreLocation

// MARK: - ElevationPoint

struct ElevationPoint: Identifiable {
    let id = UUID()
    let distance: Double // km
    let altitude: Double // m
}

// MARK: - ElevationProfileView

struct ElevationProfileView: View {
    let elevationData: [ElevationPoint]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Elevation Profile")
                .font(.headline)
                .padding(.horizontal)

            if elevationData.count >= 2 {
                Chart(elevationData) { point in
                    AreaMark(
                        x: .value("Distance (km)", point.distance),
                        y: .value("Altitude (m)", point.altitude)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.brown.opacity(0.6), .brown.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Distance (km)", point.distance),
                        y: .value("Altitude (m)", point.altitude)
                    )
                    .foregroundStyle(.brown)
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("m")
                .chartXAxisLabel("km")
                .frame(height: 150)
                .padding(.horizontal)
            } else {
                Text("Not enough data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Factory from RouteWaypoints

    /// Build elevation data from sorted `RouteWaypoint` array.
    static func elevationData(from waypoints: [RouteWaypoint]) -> [ElevationPoint] {
        guard waypoints.count >= 2 else {
            return waypoints.map { ElevationPoint(distance: 0, altitude: $0.altitude) }
        }

        var result: [ElevationPoint] = []
        var cumDist: Double = 0

        result.append(ElevationPoint(distance: 0, altitude: waypoints[0].altitude))

        for idx in 1..<waypoints.count {
            let prev = CLLocation(latitude: waypoints[idx - 1].latitude, longitude: waypoints[idx - 1].longitude)
            let curr = CLLocation(latitude: waypoints[idx].latitude, longitude: waypoints[idx].longitude)
            cumDist += curr.distance(from: prev) / 1000.0
            result.append(ElevationPoint(distance: cumDist, altitude: waypoints[idx].altitude))
        }

        return result
    }
}

#Preview {
    ElevationProfileView(elevationData: [
        ElevationPoint(distance: 0, altitude: 100),
        ElevationPoint(distance: 1.5, altitude: 150),
        ElevationPoint(distance: 3.0, altitude: 120),
        ElevationPoint(distance: 5.0, altitude: 200),
        ElevationPoint(distance: 7.0, altitude: 90)
    ])
}
