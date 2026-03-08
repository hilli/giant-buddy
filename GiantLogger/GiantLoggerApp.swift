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
    @StateObject private var stravaService = StravaService.shared

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
                .environmentObject(stravaService)
                .onOpenURL { url in
                    if url.scheme == "giantlogger" {
                        Task {
                            await stravaService.handleCallback(url)
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
