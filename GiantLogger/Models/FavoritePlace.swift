import CoreLocation
import Foundation

/// A user-saved favorite place, persisted via UserDefaults.
struct FavoritePlace: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var originalName: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from location: CLLocation) -> Double {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }
}

// MARK: - Persistence

extension FavoritePlace {
    private static let key = "searchFavorites"

    static func loadAll() -> [FavoritePlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let favorites = try? JSONDecoder().decode([FavoritePlace].self, from: data) else {
            return []
        }
        return favorites
    }

    static func saveAll(_ favorites: [FavoritePlace]) {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
