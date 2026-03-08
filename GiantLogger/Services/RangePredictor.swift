import Foundation
import CoreLocation

// MARK: - Range Prediction Engine

/// Predicts battery consumption along a route using historical ride data and elevation analysis.
@MainActor
class RangePredictor: ObservableObject {

    // MARK: - Types

    struct RoutePrediction {
        let segments: [PredictionSegment]
        let canComplete: Bool
        let estimatedEndBattery: Double
        let recommendedMode: String?
        let hasHistoricalData: Bool
    }

    struct PredictionSegment: Identifiable {
        let id = UUID()
        let distance: Double          // cumulative km from start
        let altitude: Double          // meters
        let predictedBattery: Double  // predicted % at this point
        let status: SegmentStatus
    }

    enum SegmentStatus {
        case safe       // > 20%
        case warning    // 10-20%
        case critical   // < 10%
        case depleted   // 0%

        init(battery: Double) {
            switch battery {
            case _ where battery <= 0: self = .depleted
            case ..<10:                self = .critical
            case ..<20:                self = .warning
            default:                   self = .safe
            }
        }
    }

    // MARK: - Learned Parameters

    struct ConsumptionProfile: Codable {
        var flatRate: Double       // % per km on flat terrain
        var moderateRate: Double   // % per km on moderate uphill
        var steepRate: Double      // % per km on steep uphill
        var downhillRate: Double   // % per km on downhill
        var ridesAnalyzed: Int

        static let `default` = ConsumptionProfile(
            flatRate: 1.5,
            moderateRate: 2.25,
            steepRate: 3.0,
            downhillRate: 0.75,
            ridesAnalyzed: 0
        )
    }

    // MARK: - Mode Multipliers

    private static let modeMultipliers: [String: Double] = [
        "eco": 0.5,
        "normal": 1.0,
        "normal+": 1.2,
        "tour": 0.8,
        "tour+": 1.0,
        "power": 1.5,
        "power+": 1.7,
        "boost": 2.0,
        "boost+": 2.2,
        "climb": 1.8,
        "climb+": 2.0,
        "smart": 0.9,
    ]

    /// Ordered from most efficient to most powerful for mode recommendation.
    private static let modesByEfficiency = [
        "eco", "tour", "smart", "normal", "tour+", "normal+",
        "power", "power+", "climb", "climb+", "boost", "boost+",
    ]

    private static let userDefaultsKey = "rangePredictor.consumptionRates"

    // MARK: - State

    @Published private(set) var profile: ConsumptionProfile

    init() {
        self.profile = Self.loadProfile()
    }

    // MARK: - Core Prediction

    func predict(route: Route, currentBattery: Int, assistMode: String = "normal") -> RoutePrediction {
        let waypoints = route.sortedWaypoints
        guard waypoints.count >= 2 else {
            return RoutePrediction(
                segments: [],
                canComplete: true,
                estimatedEndBattery: Double(currentBattery),
                recommendedMode: nil,
                hasHistoricalData: profile.ridesAnalyzed > 0
            )
        }

        let modeMultiplier = Self.modeMultipliers[assistMode.lowercased()] ?? 1.0
        let segments = buildSegments(waypoints: waypoints, startBattery: Double(currentBattery), modeMultiplier: modeMultiplier)

        let endBattery = segments.last?.predictedBattery ?? Double(currentBattery)
        let canComplete = endBattery > 0

        var recommendedMode: String?
        if !canComplete {
            recommendedMode = findBestMode(waypoints: waypoints, startBattery: Double(currentBattery))
        }

        return RoutePrediction(
            segments: segments,
            canComplete: canComplete,
            estimatedEndBattery: max(endBattery, 0),
            recommendedMode: recommendedMode,
            hasHistoricalData: profile.ridesAnalyzed > 0
        )
    }

    // MARK: - Learning

    func learnFromRides(_ rides: [Ride]) {
        let validRides = rides.filter { $0.totalDistance > 0.5 && $0.startBattery > $0.endBattery }
        guard !validRides.isEmpty else { return }

        var flatRates: [Double] = []
        var hillRates: [Double] = []

        for ride in validRides {
            let drain = Double(ride.startBattery - ride.endBattery)
            let ratePerKm = drain / ride.totalDistance

            let elevGainPerKm = ride.totalDistance > 0 ? ride.elevationGain / ride.totalDistance : 0

            if elevGainPerKm < 20 {
                flatRates.append(ratePerKm)
            } else {
                hillRates.append(ratePerKm)
            }
        }

        var updated = profile
        updated.ridesAnalyzed = validRides.count

        if !flatRates.isEmpty {
            updated.flatRate = flatRates.reduce(0, +) / Double(flatRates.count)
            updated.downhillRate = updated.flatRate * 0.5
        }
        if !hillRates.isEmpty {
            let avgHillRate = hillRates.reduce(0, +) / Double(hillRates.count)
            updated.moderateRate = avgHillRate
            updated.steepRate = avgHillRate * 1.33
        } else if !flatRates.isEmpty {
            updated.moderateRate = updated.flatRate * 1.5
            updated.steepRate = updated.flatRate * 2.0
        }

        profile = updated
        saveProfile(updated)
    }

    // MARK: - Consumption Rate

    func consumptionRate(forMode mode: String, elevationGainPerKm: Double) -> Double {
        let modeMultiplier = Self.modeMultipliers[mode.lowercased()] ?? 1.0
        let baseRate = baseRateForElevation(elevationGainPerKm)
        return baseRate * modeMultiplier
    }

    // MARK: - Private Helpers

    private func buildSegments(waypoints: [RouteWaypoint], startBattery: Double, modeMultiplier: Double) -> [PredictionSegment] {
        var segments: [PredictionSegment] = []
        var cumulativeDistance: Double = 0
        var battery = startBattery

        segments.append(PredictionSegment(
            distance: 0,
            altitude: waypoints[0].altitude,
            predictedBattery: battery,
            status: SegmentStatus(battery: battery)
        ))

        for i in 1..<waypoints.count {
            let prev = CLLocation(latitude: waypoints[i - 1].latitude, longitude: waypoints[i - 1].longitude)
            let curr = CLLocation(latitude: waypoints[i].latitude, longitude: waypoints[i].longitude)
            let segmentDistance = curr.distance(from: prev) / 1000.0 // km

            guard segmentDistance > 0 else {
                segments.append(PredictionSegment(
                    distance: cumulativeDistance,
                    altitude: waypoints[i].altitude,
                    predictedBattery: battery,
                    status: SegmentStatus(battery: battery)
                ))
                continue
            }

            cumulativeDistance += segmentDistance

            let elevChange = waypoints[i].altitude - waypoints[i - 1].altitude
            let elevGainPerKm = elevChange / segmentDistance // m/km, negative for downhill

            let baseRate = baseRateForGradient(elevGainPerKm)
            let drain = segmentDistance * baseRate * modeMultiplier
            battery = max(battery - drain, 0)

            segments.append(PredictionSegment(
                distance: cumulativeDistance,
                altitude: waypoints[i].altitude,
                predictedBattery: battery,
                status: SegmentStatus(battery: battery)
            ))
        }

        return segments
    }

    /// Returns base consumption rate (% per km) based on cumulative elevation gain per km.
    private func baseRateForElevation(_ elevGainPerKm: Double) -> Double {
        switch elevGainPerKm {
        case ..<0:   return profile.downhillRate
        case ..<20:  return profile.flatRate
        case ..<50:  return profile.moderateRate
        default:     return profile.steepRate
        }
    }

    /// Returns base consumption rate based on point-to-point gradient (m elevation change per km).
    private func baseRateForGradient(_ gradient: Double) -> Double {
        switch gradient {
        case ..<(-10): return profile.downhillRate
        case ..<20:    return profile.flatRate
        case ..<50:    return profile.moderateRate
        default:       return profile.steepRate
        }
    }

    private func findBestMode(waypoints: [RouteWaypoint], startBattery: Double) -> String? {
        for mode in Self.modesByEfficiency {
            let multiplier = Self.modeMultipliers[mode] ?? 1.0
            let segments = buildSegments(waypoints: waypoints, startBattery: startBattery, modeMultiplier: multiplier)
            if let last = segments.last, last.predictedBattery > 0 {
                return mode.capitalized
            }
        }
        return nil
    }

    // MARK: - Persistence

    private static func loadProfile() -> ConsumptionProfile {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(ConsumptionProfile.self, from: data) else {
            return .default
        }
        return decoded
    }

    private func saveProfile(_ profile: ConsumptionProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
