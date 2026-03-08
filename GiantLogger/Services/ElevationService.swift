import Foundation
import CoreLocation

/// Fetches elevation data from the Open-Meteo Elevation API (free, no API key required).
actor ElevationService {
    static let shared = ElevationService()

    private let baseURL = "https://api.open-meteo.com/v1/elevation"
    private let batchSize = 100 // API supports up to ~100 coordinates per request

    struct ElevationResponse: Codable {
        let elevation: [Double]
    }

    /// Fetch elevation for an array of coordinates. Returns altitudes in meters.
    func fetchElevations(for coordinates: [CLLocationCoordinate2D]) async throws -> [Double] {
        guard !coordinates.isEmpty else { return [] }

        var allElevations: [Double] = []

        for batchStart in stride(from: 0, to: coordinates.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, coordinates.count)
            let batch = Array(coordinates[batchStart..<batchEnd])

            let lats = batch.map { String(format: "%.6f", $0.latitude) }.joined(separator: ",")
            let lons = batch.map { String(format: "%.6f", $0.longitude) }.joined(separator: ",")

            guard let url = URL(string: "\(baseURL)?latitude=\(lats)&longitude=\(lons)") else {
                throw ElevationError.invalidURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw ElevationError.requestFailed
            }

            let decoded = try JSONDecoder().decode(ElevationResponse.self, from: data)
            allElevations.append(contentsOf: decoded.elevation)
        }

        return allElevations
    }

    /// Fetch elevation for a single coordinate.
    func fetchElevation(for coordinate: CLLocationCoordinate2D) async throws -> Double {
        let elevations = try await fetchElevations(for: [coordinate])
        return elevations.first ?? 0
    }

    enum ElevationError: LocalizedError {
        case invalidURL
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid elevation API URL"
            case .requestFailed: return "Elevation API request failed"
            }
        }
    }
}
