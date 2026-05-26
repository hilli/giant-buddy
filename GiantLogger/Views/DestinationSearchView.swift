import SwiftUI
@preconcurrency import MapKit
import CoreLocation

// swiftlint:disable file_length

/// Sheet for destination search with POI categories, address search, and favorites.
struct DestinationSearchView: View {
    @EnvironmentObject var navigationEngine: NavigationEngine
    @EnvironmentObject var locationManager: LocationManager
    @ObservedObject var favoritesManager: FavoritePlacesManager
    @StateObject private var poiService = POISearchService()

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: POISearchService.POICategory?
    @State private var showingFavorites = false
    @State private var renamePlace: FavoritePlace?
    @State private var renameText = ""
    @State private var completerResults: [MKLocalSearchCompletion] = []
    @StateObject private var searchCompleter = SearchCompleterDelegate()
    @State private var searchTask: Task<Void, Never>?

    private let onStartNavigation: (CLLocationCoordinate2D, String) -> Void

    init(favoritesManager: FavoritePlacesManager, onStartNavigation: @escaping (CLLocationCoordinate2D, String) -> Void) {
        self.favoritesManager = favoritesManager
        self.onStartNavigation = onStartNavigation
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                if showingFavorites {
                    favoritesSection
                } else if !searchText.isEmpty {
                    searchResultsList
                } else if selectedCategory != nil {
                    categoryResultsList
                } else {
                    recentAndHintSection
                }
            }
            .navigationTitle("Navigate To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search address or place")
            .onChange(of: searchText) { _, newValue in
                selectedCategory = nil
                showingFavorites = false
                searchCompleter.update(query: newValue, near: locationManager.currentLocation)
                // Debounced live search
                searchTask?.cancel()
                let query = newValue
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    await poiService.search(query: query, near: locationManager.currentLocation)
                }
            }
            .onSubmit(of: .search) {
                searchTask?.cancel()
                Task {
                    await poiService.search(query: searchText, near: locationManager.currentLocation)
                }
            }
            .onReceive(searchCompleter.$results) { results in
                completerResults = results
            }
            .alert("Rename Favorite", isPresented: .init(
                get: { renamePlace != nil },
                set: { if !$0 { renamePlace = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renamePlace = nil }
                Button("Save") {
                    if let place = renamePlace, !renameText.isEmpty {
                        favoritesManager.rename(place, to: renameText)
                    }
                    renamePlace = nil
                }
            }
        }
    }

    // MARK: - Category Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(
                    label: "Favorites",
                    icon: "star.fill",
                    color: .orange,
                    isSelected: showingFavorites
                ) {
                    showingFavorites = true
                    selectedCategory = nil
                    searchText = ""
                }

                ForEach(POISearchService.POICategory.allCases) { category in
                    categoryChip(
                        label: category.rawValue,
                        icon: category.icon,
                        color: category.color,
                        isSelected: selectedCategory == category && !showingFavorites
                    ) {
                        selectedCategory = category
                        showingFavorites = false
                        searchText = ""
                        Task {
                            await poiService.searchCategory(category, near: locationManager.currentLocation)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func categoryChip(label: String, icon: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? color : .secondary)
        .buttonBorderShape(.capsule)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            if !completerResults.isEmpty && poiService.searchResults.isEmpty {
                Section("Suggestions") {
                    ForEach(completerResults, id: \.self) { completion in
                        Button {
                            Task {
                                searchText = completion.title
                                await poiService.search(query: completion.title, near: locationManager.currentLocation)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.body)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            if !poiService.searchResults.isEmpty {
                Section("Results") {
                    ForEach(poiService.searchResults) { result in
                        poiResultRow(result)
                    }
                }
            }

            if poiService.isSearching {
                HStack {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Category Results

    private var categoryResultsList: some View {
        List {
            if poiService.isSearching {
                HStack {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if poiService.searchResults.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "mappin.slash",
                    description: Text("No places found nearby.")
                )
            } else {
                ForEach(poiService.searchResults) { result in
                    poiResultRow(result)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        let sorted = favoritesManager.sorted(from: locationManager.currentLocation)
        return Group {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("Long-press a search result to add it to favorites.")
                )
            } else {
                List {
                    ForEach(sorted) { place in
                        favoriteRow(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    favoritesManager.delete(place)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    renameText = place.name
                                    renamePlace = place
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    favoritesManager.togglePin(place)
                                } label: {
                                    Label(
                                        place.isPinned ? "Unpin" : "Pin to Top",
                                        systemImage: place.isPinned ? "pin.slash" : "pin.fill"
                                    )
                                }
                                Button {
                                    renameText = place.name
                                    renamePlace = place
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    favoritesManager.delete(place)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Recents & Hints

    private var recentAndHintSection: some View {
        List {
            if !poiService.recentSearches.isEmpty {
                Section("Recent Searches") {
                    ForEach(poiService.recentSearches, id: \.self) { recent in
                        Button {
                            searchText = recent
                            Task {
                                await poiService.search(query: recent, near: locationManager.currentLocation)
                            }
                        } label: {
                            Label(recent, systemImage: "clock.arrow.circlepath")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section {
                VStack(spacing: 12) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Search for an address, place, or tap a category above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Row Views

    private func poiResultRow(_ result: POISearchService.POIResult) -> some View {
        Button {
            startNavigation(to: result.coordinate, name: result.name)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(result.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let distance = result.distance {
                    Text(formattedDistance(distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        }
        .contextMenu {
            Button {
                favoritesManager.add(
                    name: result.name,
                    coordinate: result.coordinate,
                    address: result.address
                )
            } label: {
                Label("Add to Favorites", systemImage: "star")
            }
            Button {
                startNavigation(to: result.coordinate, name: result.name)
            } label: {
                Label("Navigate", systemImage: "location.fill")
            }
        }
    }

    private func favoriteRow(_ place: FavoritePlace) -> some View {
        Button {
            startNavigation(to: place.coordinate, name: place.name)
        } label: {
            HStack {
                if place.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(place.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let location = locationManager.currentLocation {
                    Text(formattedDistance(place.distance(from: location)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Helpers

    private func startNavigation(to coordinate: CLLocationCoordinate2D, name: String) {
        onStartNavigation(coordinate, name)
        dismiss()
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
}

// MARK: - MKLocalSearchCompleter Delegate

@MainActor
class SearchCompleterDelegate: NSObject, ObservableObject, @MainActor MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func update(query: String, near location: CLLocation?) {
        if let location {
            completer.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
