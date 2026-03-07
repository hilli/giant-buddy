import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var bikeService: GiantBikeService
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var rideRecorder: RideRecorder
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var stravaService: StravaService
    @Environment(\.modelContext) private var modelContext

    @State private var hasConfigured = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Ride", systemImage: "figure.outdoor.cycle")
                }

            RideListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ConnectionView()
                .tabItem {
                    Label("Bike", systemImage: "bicycle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.accentColor)
        .onAppear {
            if !hasConfigured {
                bikeService.attach(to: bikeManager)
                rideRecorder.configure(
                    bikeService: bikeService,
                    locationManager: locationManager,
                    workoutManager: workoutManager,
                    stravaService: stravaService,
                    modelContext: modelContext
                )
                if UserDefaults.standard.bool(forKey: "logWorkouts") {
                    workoutManager.requestAuthorization()
                }
                hasConfigured = true
            }
        }
    }
}
