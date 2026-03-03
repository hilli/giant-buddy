import Foundation
import WeatherKit
import CoreLocation

/// Fetches and caches current weather + hourly forecast using WeatherKit.
@MainActor
class WeatherManager: ObservableObject {

    @Published var currentWeather: CurrentWeather?
    @Published var hourlyForecast: [HourWeather] = []

    private let service = WeatherService.shared
    private var refreshTimer: Timer?
    private var lastFetchLocation: CLLocation?

    func fetchWeather(for location: CLLocation) async {
        // Skip if location hasn't changed significantly (within 500m) and we have data
        if let last = lastFetchLocation,
           last.distance(from: location) < 500,
           currentWeather != nil {
            return
        }

        do {
            let (current, hourly) = try await service.weather(
                for: location,
                including: .current, .hourly
            )
            currentWeather = current
            // Filter to next 3 hours (excluding the current hour)
            let now = Date()
            hourlyForecast = Array(
                hourly.filter { $0.date > now }.prefix(3)
            )
            lastFetchLocation = location
        } catch {
            print("WeatherManager: failed to fetch weather: \(error)")
        }
    }

    /// Force a refresh regardless of location change.
    func refresh(for location: CLLocation) async {
        lastFetchLocation = nil
        await fetchWeather(for: location)
    }
}
