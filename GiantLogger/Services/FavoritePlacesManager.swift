import Foundation
import CoreLocation

/// Manages favorite places with iCloud sync via NSUbiquitousKeyValueStore.
@MainActor
class FavoritePlacesManager: ObservableObject {

    @Published var favorites: [FavoritePlace] = []

    private static let storageKey = "favoritePlaces"
    private static let legacyKey = "searchFavorites"
    private let iCloudStore = NSUbiquitousKeyValueStore.default

    init() {
        loadFavorites()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore
        )
        iCloudStore.synchronize()
    }

    // MARK: - CRUD

    func add(_ place: FavoritePlace) {
        guard !favorites.contains(where: { $0.id == place.id }) else { return }
        favorites.append(place)
        save()
    }

    func add(name: String, coordinate: CLLocationCoordinate2D, address: String) {
        let place = FavoritePlace(
            id: UUID(),
            name: name,
            originalName: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            isPinned: false
        )
        add(place)
    }

    func delete(_ place: FavoritePlace) {
        favorites.removeAll { $0.id == place.id }
        save()
    }

    func delete(at offsets: IndexSet, from sorted: [FavoritePlace]) {
        let idsToDelete = offsets.map { sorted[$0].id }
        favorites.removeAll { idsToDelete.contains($0.id) }
        save()
    }

    func rename(_ place: FavoritePlace, to newName: String) {
        guard let idx = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[idx].name = newName
        save()
    }

    func togglePin(_ place: FavoritePlace) {
        guard let idx = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[idx].isPinned.toggle()
        save()
    }

    /// Returns favorites sorted: pinned first (alphabetical), then unpinned by distance.
    func sorted(from location: CLLocation?) -> [FavoritePlace] {
        let pinned = favorites.filter { $0.isPinned }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let unpinned = favorites.filter { !$0.isPinned }
        if let location {
            let sorted = unpinned.sorted { $0.distance(from: location) < $1.distance(from: location) }
            return pinned + sorted
        }
        return pinned + unpinned.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        iCloudStore.set(data, forKey: Self.storageKey)
        iCloudStore.synchronize()
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadFavorites() {
        // Prefer iCloud data
        if let data = iCloudStore.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FavoritePlace].self, from: data) {
            favorites = decoded
            return
        }
        // Fall back to new key in local storage
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FavoritePlace].self, from: data) {
            favorites = decoded
            return
        }
        // Migrate from legacy key
        if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
           let decoded = try? JSONDecoder().decode([FavoritePlace].self, from: data) {
            favorites = decoded
            save()
        }
    }

    @objc private func iCloudDidChange(_ notification: Notification) {
        Task { @MainActor in
            loadFavorites()
        }
    }
}
