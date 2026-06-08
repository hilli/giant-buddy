import SwiftUI
import MapKit

/// POI and address search view, intended to be presented as a sheet.
struct SearchView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var navigationEngine: NavigationEngine
    @EnvironmentObject var favoritePlacesManager: FavoritePlacesManager
    @StateObject private var searchService = POISearchService()

    @State private var searchText = ""
    @State private var selectedResult: POISearchService.POIResult?
    @State private var showingMap = false
    @State private var activeCategory: POISearchService.POICategory?
    @State private var renamingFavorite: FavoritePlace?
    @State private var renameText = ""
    @State private var searchTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !locationManager.locationIsAuthorized {
                    locationPermissionView
                } else {
                    searchContent
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingMap) {
                SearchResultsMapView(
                    results: searchService.searchResults,
                    selectedResult: selectedResult,
                    searchTitle: activeCategory?.rawValue ?? searchText
                )
                .environmentObject(locationManager)
                .environmentObject(navigationEngine)
            }
            .onAppear { }
            .alert("Rename Favorite", isPresented: Binding(
                get: { renamingFavorite != nil },
                set: { if !$0 { renamingFavorite = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let fav = renamingFavorite {
                        favoritePlacesManager.rename(fav, to: renameText.trimmingCharacters(in: .whitespaces))
                    }
                    renamingFavorite = nil
                }
                Button("Cancel", role: .cancel) { renamingFavorite = nil }
            } message: {
                Text("Enter a custom name like \"Home\" or \"Work\"")
            }
        }
    }

    // MARK: - Search Content

    private var searchContent: some View {
        VStack(spacing: 0) {
            searchBar

            if searchText.isEmpty && !favoritePlacesManager.favorites.isEmpty {
                FavoritesSectionView(
                    favorites: favoritePlacesManager.favorites,
                    currentLocation: locationManager.currentLocation,
                    onSelect: { fav in selectFavorite(fav) },
                    onRename: { fav in
                        renamingFavorite = fav
                        renameText = fav.name
                    },
                    onRemove: { fav in removeFavorite(fav) }
                )
            }

            categoryButtons

            if searchService.isSearching {
                Spacer()
                ProgressView("Searching…")
                Spacer()
            } else if !searchService.searchResults.isEmpty {
                resultsList
            } else if searchText.isEmpty && !searchService.recentSearches.isEmpty {
                recentsList
            } else if !searchText.isEmpty {
                emptyState
            } else {
                emptyState
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search places or addresses", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchText) { _, newValue in
                    searchTask?.cancel()
                    guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                        searchService.searchResults = []
                        return
                    }
                    activeCategory = nil
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await searchService.search(query: newValue, near: locationManager.currentLocation)
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchService.searchResults = []
                    activeCategory = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Category Buttons

    private var categoryButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(POISearchService.POICategory.allCases) { category in
                    Button {
                        searchText = ""
                        activeCategory = category
                        Task {
                            await searchService.searchCategory(category, near: locationManager.currentLocation)
                        }
                    } label: {
                        Label(category.rawValue, systemImage: category.icon)
                            .font(.subheadline)
                            .fontWeight(activeCategory == category ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                activeCategory == category
                                    ? category.color.opacity(0.2)
                                    : Color(.systemGray6)
                            )
                            .foregroundStyle(activeCategory == category ? category.color : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List(searchService.searchResults) { result in
            Button {
                selectedResult = result
                showingMap = true
            } label: {
                POIResultRow(result: result)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !favoritePlacesManager.favorites.contains(where: {
                    $0.latitude == result.coordinate.latitude
                        && $0.longitude == result.coordinate.longitude
                }) {
                    Button {
                        addToFavorites(result)
                    } label: {
                        Label("Add to Favorites", systemImage: "star")
                    }
                } else {
                    Button {
                        if let fav = favoritePlacesManager.favorites.first(where: {
                            $0.latitude == result.coordinate.latitude
                                && $0.longitude == result.coordinate.longitude
                        }) {
                            removeFavorite(fav)
                        }
                    } label: {
                        Label("Remove from Favorites", systemImage: "star.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Recents List

    private var recentsList: some View {
        List {
            Section {
                ForEach(searchService.recentSearches, id: \.self) { query in
                    Button {
                        searchText = query
                        performSearch()
                    } label: {
                        Label(query, systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Recent Searches")
                    Spacer()
                    Button("Clear") {
                        searchService.clearRecents()
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Favorites Helpers

    private func selectFavorite(_ fav: FavoritePlace) {
        let result = POISearchService.POIResult(
            name: fav.originalName,
            address: fav.address,
            coordinate: fav.coordinate,
            category: nil,
            distance: locationManager.currentLocation.map { fav.distance(from: $0) },
            mapItem: MKMapItem(coordinate: fav.coordinate)
        )
        selectedResult = result
        searchService.searchResults = [result]
        showingMap = true
    }

    private func addToFavorites(_ result: POISearchService.POIResult) {
        favoritePlacesManager.add(name: result.name, coordinate: result.coordinate, address: result.address)
    }

    private func removeFavorite(_ fav: FavoritePlace) {
        favoritePlacesManager.delete(fav)
    }

    // MARK: - Helpers

    private func performSearch() {
        activeCategory = nil
        Task {
            await searchService.search(query: searchText, near: locationManager.currentLocation)
        }
    }
}

// MARK: - SearchView Subviews

private extension SearchView {
    var emptyState: some View {
        ContentUnavailableView(
            "Search Nearby",
            systemImage: "magnifyingglass",
            description: Text("Find toilets, bike shops, charging stations, and cafés near you.")
        )
    }

    var locationPermissionView: some View {
        ContentUnavailableView {
            Label("Location Required", systemImage: "location.slash")
        } description: {
            Text("Enable location access so we can find places near you.")
        } actions: {
            Button("Enable Location") {
                locationManager.requestPermission()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - POIResultRow

struct POIResultRow: View {
    let result: POISearchService.POIResult

    var body: some View {
        HStack(spacing: 12) {
            if let category = result.category {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(category.color)
                    .frame(width: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.headline)
                    .lineLimit(1)
                if !result.address.isEmpty {
                    Text(result.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let distance = result.distance {
                Text(formattedDistance(distance))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}

// MARK: - Location Authorization Helper

private extension LocationManager {
    var locationIsAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }
}
