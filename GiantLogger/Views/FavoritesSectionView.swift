import MapKit
import SwiftUI

/// Horizontal scrolling favorites cards, shown when the search field is empty.
struct FavoritesSectionView: View {
    let favorites: [FavoritePlace]
    let currentLocation: CLLocation?
    var onSelect: (FavoritePlace) -> Void
    var onRename: (FavoritePlace) -> Void
    var onRemove: (FavoritePlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Favorites")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sortedFavorites) { fav in
                        favoriteCard(fav)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private var sortedFavorites: [FavoritePlace] {
        guard let location = currentLocation else { return favorites }
        return favorites.sorted { $0.distance(from: location) < $1.distance(from: location) }
    }

    private func favoriteCard(_ fav: FavoritePlace) -> some View {
        Button {
            onSelect(fav)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: favoriteIcon(for: fav.name))
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(fav.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                if let location = currentLocation {
                    Text(formattedDistance(fav.distance(from: location)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onRename(fav)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onRemove(fav)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func favoriteIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("home") { return "house.fill" }
        if lower.contains("work") || lower.contains("office") { return "building.2.fill" }
        return "star.fill"
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters)) m" }
        return String(format: "%.1f km", meters / 1000)
    }
}
