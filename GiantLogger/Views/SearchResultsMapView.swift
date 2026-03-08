import SwiftUI
import MapKit

/// Map view displaying POI search results with optional cycling directions.
struct SearchResultsMapView: View {
    let results: [POISearchService.POIResult]
    let selectedResult: POISearchService.POIResult?
    let searchTitle: String

    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var navigationEngine: NavigationEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = POISearchService()

    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var pickedResult: POISearchService.POIResult?
    @State private var route: MKRoute?
    @State private var isLoadingRoute = false

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent
            if let picked = pickedResult {
                detailCard(for: picked)
            }
            if isLoadingRoute {
                ProgressView("Calculating route…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, pickedResult != nil ? 180 : 16)
            }
        }
        .navigationTitle(searchTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pickedResult = selectedResult
            updateCamera()
        }
    }

    // MARK: - Map

    private var mapContent: some View {
        Map(position: $mapCameraPosition) {
            UserAnnotation()

            ForEach(results) { result in
                Annotation(result.name, coordinate: result.coordinate) {
                    annotationView(for: result)
                        .onTapGesture {
                            withAnimation {
                                pickedResult = result
                                route = nil
                            }
                        }
                }
            }

            if let route {
                MapPolyline(route.polyline)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Annotation View

    private func annotationView(for result: POISearchService.POIResult) -> some View {
        let isSelected = pickedResult?.id == result.id
        let color = result.category?.color ?? .red

        return Image(systemName: result.category?.icon ?? "mappin.circle.fill")
            .font(isSelected ? .title : .title3)
            .foregroundStyle(.white)
            .padding(6)
            .background(color, in: Circle())
            .shadow(radius: isSelected ? 4 : 2)
    }

    // MARK: - Detail Card

    private func detailCard(for result: POISearchService.POIResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.headline)
                    if !result.address.isEmpty {
                        Text(result.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let distance = result.distance {
                        Text(formattedDistance(distance))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    withAnimation { pickedResult = nil; route = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if let route {
                routeSummary(route)
            }

            HStack(spacing: 12) {
                Button {
                    loadDirections(to: result)
                } label: {
                    Label("Directions", systemImage: "bicycle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(locationManager.currentLocation == nil || isLoadingRoute)

                Button {
                    result.mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeCycling
                    ])
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                startNavigation(to: result)
            } label: {
                Label("Start Navigation", systemImage: "location.north.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(locationManager.currentLocation == nil)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Route Summary

    private func routeSummary(_ route: MKRoute) -> some View {
        HStack(spacing: 16) {
            Label(formattedDistance(route.distance), systemImage: "arrow.triangle.swap")
                .font(.subheadline)
            Label(formattedDuration(route.expectedTravelTime), systemImage: "clock")
                .font(.subheadline)
        }
        .foregroundStyle(.blue)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func updateCamera() {
        if let selected = selectedResult {
            mapCameraPosition = .region(MKCoordinateRegion(
                center: selected.coordinate,
                latitudinalMeters: 2000,
                longitudinalMeters: 2000
            ))
        } else if let location = locationManager.currentLocation {
            mapCameraPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            ))
        }
    }

    private func loadDirections(to result: POISearchService.POIResult) {
        guard let location = locationManager.currentLocation else { return }
        isLoadingRoute = true
        Task {
            route = await searchService.getDirections(to: result, from: location)
            isLoadingRoute = false
        }
    }

    private func startNavigation(to result: POISearchService.POIResult) {
        guard let userLocation = locationManager.currentLocation else { return }

        let navRoute = Route(name: result.name, source: "search_navigation")

        let startWP = RouteWaypoint(
            index: 0,
            latitude: userLocation.coordinate.latitude,
            longitude: userLocation.coordinate.longitude,
            altitude: userLocation.altitude
        )
        let endWP = RouteWaypoint(
            index: 1,
            latitude: result.coordinate.latitude,
            longitude: result.coordinate.longitude
        )

        navRoute.waypoints = [startWP, endWP]
        navRoute.recalculateStats()

        Task {
            await navigationEngine.calculateDirections(for: navRoute)
        }

        NotificationCenter.default.post(name: .switchToRideTab, object: nil)
        dismiss()
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours) h \(remainingMinutes) min"
        }
    }
}
