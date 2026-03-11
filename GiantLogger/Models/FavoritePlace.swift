import CoreLocation
import Foundation

/// A user-saved favorite place, persisted via iCloud (NSUbiquitousKeyValueStore).
struct FavoritePlace: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var originalName: String
    var address: String
    var latitude: Double
    var longitude: Double
    var isPinned: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from location: CLLocation) -> Double {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }
}
