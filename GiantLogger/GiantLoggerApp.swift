import SwiftUI
import SwiftData

@main
struct GiantLoggerApp: App {
    @StateObject private var bikeManager = BikeManager()
    @StateObject private var bikeService = GiantBikeService()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var rideRecorder = RideRecorder()
    @StateObject private var weatherManager = WeatherManager()
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var crashDetector = CrashDetector()
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var navigationEngine = NavigationEngine()
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Ride.self, RideSample.self, Route.self, RouteWaypoint.self, MaintenanceItem.self, BatterySnapshot.self, ErrorLogEntry.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

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
                .onAppear {
                    watchConnectivity.activate()
                    watchConnectivity.onStartRecording = { [weak rideRecorder] in
                        rideRecorder?.startRecording()
                    }
                    watchConnectivity.onStopRecording = { [weak rideRecorder] in
                        rideRecorder?.stopRecording()
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "giantlogger" else { return }
                    if url.host == "lastride" {
                        NotificationCenter.default.post(name: .switchToHistoryTab, object: nil)
                    } else {
                        Task {
                            await stravaService.handleCallback(url)
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
