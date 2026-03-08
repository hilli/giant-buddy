import Foundation
import MapKit
import CoreLocation
import SwiftUI

/// Search service for nearby points of interest and addresses using MapKit.
@MainActor
class POISearchService: ObservableObject {

    @Published var searchResults: [POIResult] = []
    @Published var isSearching: Bool = false
    @Published var recentSearches: [String] = []

    private static let recentSearchesKey = "recentPOISearches"
    private static let maxRecentSearches = 10
    private static let searchRadiusMeters: CLLocationDistance = 10_000

    private var currentSearch: MKLocalSearch?

    // MARK: - POI Category

    /// Search categories relevant to cyclists.
    enum POICategory: String, CaseIterable, Identifiable {
        case toilet = "Public Toilet"
        case bikeShop = "Bicycle Repair"
        case charging = "Charging Station"
        case cafe = "Café"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .toilet:   return "toilet"
            case .bikeShop: return "wrench.and.screwdriver"
            case .charging: return "ev.plug.dc.ccs2"
            case .cafe:     return "cup.and.saucer"
            }
        }

        var searchQuery: String {
            switch self {
            case .toilet:   return "public toilet restroom"
            case .bikeShop: return "bicycle repair bike shop"
            case .charging: return "EV charging station"
            case .cafe:     return "café coffee shop"
            }
        }

        var color: Color {
            switch self {
            case .toilet:   return .blue
            case .bikeShop: return .orange
            case .charging: return .green
            case .cafe:     return .brown
            }
        }
    }

    // MARK: - POI Result

    struct POIResult: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
        let category: POICategory?
        let distance: Double?
        let mapItem: MKMapItem
    }

    // MARK: - Init

    init() {
        loadRecentSearches()
    }

    // MARK: - Search

    /// Free-text address or place search near the user's location.
    func search(query: String, near location: CLLocation?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        currentSearch?.cancel()
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: Self.searchRadiusMeters,
                longitudinalMeters: Self.searchRadiusMeters
            )
        }

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            let results = response.mapItems.map { item in
                makeResult(from: item, category: nil, userLocation: location)
            }
            searchResults = sortedByDistance(results)
            addToRecents(trimmed)
        } catch {
            if (error as NSError).code != MKError.placemarkNotFound.rawValue {
                print("POISearchService: search error – \(error.localizedDescription)")
            }
            searchResults = []
        }

        isSearching = false
    }

    /// Category-based search for nearby POIs.
    func searchCategory(_ category: POICategory, near location: CLLocation?) async {
        currentSearch?.cancel()
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.searchQuery
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: Self.searchRadiusMeters,
                longitudinalMeters: Self.searchRadiusMeters
            )
        }

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            let results = response.mapItems.map { item in
                makeResult(from: item, category: category, userLocation: location)
            }
            searchResults = sortedByDistance(results)
        } catch {
            if (error as NSError).code != MKError.placemarkNotFound.rawValue {
                print("POISearchService: category search error – \(error.localizedDescription)")
            }
            searchResults = []
        }

        isSearching = false
    }

    // MARK: - Directions

    /// Get cycling directions to a POI result, falling back to walking if unavailable.
    func getDirections(to destination: POIResult, from location: CLLocation) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = destination.mapItem
        request.transportType = .cycling

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            return response.routes.first
        } catch {
            // Fall back to walking directions
            request.transportType = .walking
            let fallback = MKDirections(request: request)
            do {
                let response = try await fallback.calculate()
                return response.routes.first
            } catch {
                print("POISearchService: directions error – \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Recent Searches

    func addToRecents(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > Self.maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(Self.maxRecentSearches))
        }
        saveRecentSearches()
    }

    func clearRecents() {
        recentSearches = []
        saveRecentSearches()
    }

    // MARK: - Private Helpers

    private func makeResult(from item: MKMapItem, category: POICategory?, userLocation: CLLocation?) -> POIResult {
        let placemark = item.placemark
        let address = [
            placemark.thoroughfare,
            placemark.subThoroughfare,
            placemark.locality
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        var distance: Double?
        if let userLocation {
            distance = userLocation.distance(from: CLLocation(
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            ))
        }

        return POIResult(
            name: item.name ?? "Unknown",
            address: address.isEmpty ? (placemark.title ?? "") : address,
            coordinate: placemark.coordinate,
            category: category,
            distance: distance,
            mapItem: item
        )
    }

    private func sortedByDistance(_ results: [POIResult]) -> [POIResult] {
        results.sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
    }

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) ?? []
    }

    private func saveRecentSearches() {
        UserDefaults.standard.set(recentSearches, forKey: Self.recentSearchesKey)
    }
}
