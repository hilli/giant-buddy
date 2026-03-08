import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var bikeService: GiantBikeService
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var rideRecorder: RideRecorder
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var crashDetector: CrashDetector
    @EnvironmentObject var stravaService: StravaService
    @Environment(\.modelContext) private var modelContext

    @State private var hasConfigured = false
    @State private var showSearch = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Ride", systemImage: "figure.outdoor.cycle")
                }

            MyRoutesView()
                .tabItem {
                    Label("My Routes", systemImage: "map")
                }

            RideListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .fullScreenCover(isPresented: $crashDetector.isCrashDetected) {
            CrashAlertView(crashDetector: crashDetector, location: locationManager.currentLocation)
        }
        .tint(.accentColor)
        .onChange(of: rideRecorder.isRecording) { _, isRecording in
            let enabled = UserDefaults.standard.bool(forKey: "crashDetectionEnabled")
            if isRecording && enabled {
                crashDetector.startMonitoring()
            } else {
                crashDetector.stopMonitoring()
            }
        }
        .onAppear {
            if !hasConfigured {
                bikeService.attach(to: bikeManager)
                bikeService.modelContext = modelContext
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
                crashDetector.locationProvider = { [weak locationManager] in
                    locationManager?.currentLocation
                }
                hasConfigured = true
            }
        }
    }
}
