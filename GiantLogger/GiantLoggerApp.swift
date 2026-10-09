import SwiftUI
import SwiftData
import OSLog

@main
struct GiantLoggerApp: App {

    // MARK: - Service instances (created once via static bootstrap)

    @StateObject private var bikeManager: BikeManager
    @StateObject private var bikeService: GiantBikeService
    @StateObject private var locationManager: LocationManager
    @StateObject private var rideRecorder: RideRecorder
    @StateObject private var weatherManager: WeatherManager
    @StateObject private var workoutManager: WorkoutManager
    @StateObject private var crashDetector: CrashDetector
    @StateObject private var stravaService: StravaService
    @StateObject private var navigationEngine: NavigationEngine
    @StateObject private var watchConnectivity: WatchConnectivityManager
    @StateObject private var favoritePlacesManager: FavoritePlacesManager

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Shared containers

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([Ride.self, RideSample.self, Route.self, RouteWaypoint.self, MaintenanceItem.self, BatterySnapshot.self, ErrorLogEntry.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: ScreenshotMode.isEnabled,
            cloudKitDatabase: ScreenshotMode.isEnabled ? .none : .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Single-initialization bootstrap so services are wired before any BLE
    // callback can fire — works for both foreground and background launches.
    // Using nonisolated(unsafe) is safe because App.init() always runs on the
    // main thread.
    private struct Services {
        let bikeManager: BikeManager
        let bikeService: GiantBikeService
        let locationManager: LocationManager
        let rideRecorder: RideRecorder
        let weatherManager: WeatherManager
        let workoutManager: WorkoutManager
        let crashDetector: CrashDetector
        let stravaService: StravaService
        let navigationEngine: NavigationEngine
        let watchConnectivity: WatchConnectivityManager
        let favoritePlacesManager: FavoritePlacesManager
    }

    nonisolated(unsafe) private static var _services: Services?

    private static func createServices() -> Services {
        let modelContext = sharedModelContainer.mainContext

        let bikeManager = BikeManager()
        let bikeService = GiantBikeService()
        let locationManager = LocationManager()
        let rideRecorder = RideRecorder()
        let weatherManager = WeatherManager()
        let workoutManager = WorkoutManager()
        let crashDetector = CrashDetector()
        let stravaService = StravaService.shared
        let navigationEngine = NavigationEngine()
        let watchConnectivity = WatchConnectivityManager.shared
        let favoritePlacesManager = FavoritePlacesManager()

        // Wire services eagerly — this is the critical fix for background
        // launches where .onAppear never fires.
        bikeService.attach(to: bikeManager)
        bikeService.modelContext = modelContext
        rideRecorder.configure(
            bikeService: bikeService,
            locationManager: locationManager,
            workoutManager: workoutManager,
            stravaService: stravaService,
            navigationEngine: navigationEngine,
            modelContext: modelContext
        )
        if UserDefaults.standard.bool(forKey: "logWorkouts") {
            workoutManager.requestAuthorization()
        }
        crashDetector.locationProvider = { [weak locationManager] in
            locationManager?.currentLocation
        }
        watchConnectivity.activate()
        watchConnectivity.onStartRecording = { [weak rideRecorder] in
            rideRecorder?.startRecording()
        }
        watchConnectivity.onStopRecording = { [weak rideRecorder] in
            rideRecorder?.stopRecording()
        }

        return Services(
            bikeManager: bikeManager,
            bikeService: bikeService,
            locationManager: locationManager,
            rideRecorder: rideRecorder,
            weatherManager: weatherManager,
            workoutManager: workoutManager,
            crashDetector: crashDetector,
            stravaService: stravaService,
            navigationEngine: navigationEngine,
            watchConnectivity: watchConnectivity,
            favoritePlacesManager: favoritePlacesManager
        )
    }

    // MARK: - Initialization

    init() {
        let services: Services
        if let existing = Self._services {
            services = existing
        } else {
            services = Self.createServices()
            Self._services = services
            if ScreenshotMode.isEnabled {
                ScreenshotMode.seed(
                    bikeManager: services.bikeManager,
                    bikeService: services.bikeService,
                    locationManager: services.locationManager,
                    rideRecorder: services.rideRecorder,
                    modelContext: Self.sharedModelContainer.mainContext
                )
            }
        }

        _bikeManager = StateObject(wrappedValue: services.bikeManager)
        _bikeService = StateObject(wrappedValue: services.bikeService)
        _locationManager = StateObject(wrappedValue: services.locationManager)
        _rideRecorder = StateObject(wrappedValue: services.rideRecorder)
        _weatherManager = StateObject(wrappedValue: services.weatherManager)
        _workoutManager = StateObject(wrappedValue: services.workoutManager)
        _crashDetector = StateObject(wrappedValue: services.crashDetector)
        _stravaService = StateObject(wrappedValue: services.stravaService)
        _navigationEngine = StateObject(wrappedValue: services.navigationEngine)
        _watchConnectivity = StateObject(wrappedValue: services.watchConnectivity)
        _favoritePlacesManager = StateObject(wrappedValue: services.favoritePlacesManager)
    }

    // MARK: - GPX Import

    private static let importLogger = Logger(
        subsystem: "dk.hilli.GiantLogger", category: "GPXImport"
    )

    /// Import a GPX file from another app (Files, Safari, email, etc.)
    private static func importGPXFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let route = try GPXParser.parse(data: data)
            let context = sharedModelContainer.mainContext
            context.insert(route)
            try context.save()

            importLogger.info("Imported GPX route: \(route.name)")
            NotificationCenter.default.post(
                name: .gpxImportResult,
                object: GPXImportResult(
                    routeName: route.name,
                    error: nil
                )
            )
        } catch {
            importLogger.error("GPX import failed: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .gpxImportResult,
                object: GPXImportResult(
                    routeName: nil,
                    error: error.localizedDescription
                )
            )
        }
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bikeManager)
                .environmentObject(bikeService)
                .environmentObject(locationManager)
                .environmentObject(rideRecorder)
                .environmentObject(weatherManager)
                .environmentObject(workoutManager)
                .environmentObject(crashDetector)
                .environmentObject(stravaService)
                .environmentObject(navigationEngine)
                .environmentObject(watchConnectivity)
                .environmentObject(favoritePlacesManager)
                .onChange(of: scenePhase) { _, newPhase in
                    guard !ScreenshotMode.isEnabled else { return }
                    if newPhase == .active {
                        bikeManager.startForegroundAutoReconnectLoop()
                        Task { await rideRecorder.savePendingWorkouts() }
                    } else if newPhase == .background {
                        bikeManager.stopForegroundAutoReconnectLoop()
                        bikeManager.ensurePendingConnect()
                    }
                }
                .onOpenURL { url in
                    if url.scheme == "giantlogger" {
                        if url.host == "lastride" {
                            NotificationCenter.default.post(
                                name: .switchToHistoryTab, object: nil
                            )
                        } else {
                            Task { await stravaService.handleCallback(url) }
                        }
                    } else if url.isFileURL,
                              url.pathExtension.lowercased() == "gpx" {
                        Self.importGPXFile(url)
                    }
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

// MARK: - GPX Import Result

struct GPXImportResult {
    let routeName: String?
    let error: String?
}
