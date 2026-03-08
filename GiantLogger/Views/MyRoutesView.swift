import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MyRoutesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdDate, order: .reverse) private var routes: [Route]

    @State private var showFileImporter = false
    @State private var showRouteEditor = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var renamingRoute: Route?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "No Routes Yet",
                        systemImage: "map",
                        description: Text("Import a GPX file to add your first route.")
                    )
                } else {
                    List {
                        ForEach(routes) { route in
                            NavigationLink(destination: RouteMapView(route: route)) {
                                RouteRowView(route: route)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    renameText = route.name
                                    renamingRoute = route
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    modelContext.delete(route)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Routes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import GPX", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showRouteEditor = true
                        } label: {
                            Label("Create Route", systemImage: "pencil.and.outline")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showRouteEditor) {
                NavigationStack {
                    RouteEditorView()
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.xml, UTType(filenameExtension: "gpx") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Import Error", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "An unknown error occurred.")
            }
            .alert("Rename Route", isPresented: Binding(
                get: { renamingRoute != nil },
                set: { if !$0 { renamingRoute = nil } }
            )) {
                TextField("Route name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingRoute = nil }
                Button("Save") {
                    if let route = renamingRoute, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        route.name = renameText.trimmingCharacters(in: .whitespaces)
                    }
                    renamingRoute = nil
                }
            } message: {
                Text("Enter a new name for this route.")
            }
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                let route = try GPXParser.parse(data: data)
                modelContext.insert(route)
                try modelContext.save()
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }

        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
        }
    }
}

// MARK: - Route Row

private struct RouteRowView: View {
    let route: Route

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(route.formattedDistance, systemImage: "arrow.left.and.right")
                    Label(String(format: "%.0f m ↑", route.elevationGain), systemImage: "mountain.2")
                    Label("\(route.sortedWaypoints.count) pts", systemImage: "mappin.and.ellipse")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let lastRidden = route.lastRiddenDate {
                    Text("Last ridden \(lastRidden, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceIcon: String {
        switch route.source {
        case "gpx_import": return "doc.text"
        case "ride_conversion": return "bicycle"
        case "manual": return "pencil"
        default: return "map"
        }
    }
}

#Preview {
    MyRoutesView()
        .modelContainer(for: [Route.self, RouteWaypoint.self], inMemory: true)
}
