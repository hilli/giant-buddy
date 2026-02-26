import SwiftUI
import SwiftData

@main
struct GiantLoggerApp: App {
    @StateObject private var bikeManager = BikeManager()
    @StateObject private var bikeService = GiantBikeService()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var rideRecorder = RideRecorder()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bikeManager)
                .environmentObject(bikeService)
                .environmentObject(locationManager)
                .environmentObject(rideRecorder)
        }
        .modelContainer(for: [Ride.self, RideSample.self])
    }
}
