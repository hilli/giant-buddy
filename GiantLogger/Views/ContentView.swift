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
    @EnvironmentObject var navigationEngine: NavigationEngine
    @Environment(\.modelContext) private var modelContext

    @State private var hasConfigured = false
    @State private var showSearch = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(0)
                .tabItem {
                    Label("Ride", systemImage: "figure.outdoor.cycle")
                }

            MyRoutesView()
                .tag(1)
                .tabItem {
                    Label("My Routes", systemImage: "map")
                }

            RideListView()
                .tag(2)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            AnalyticsView()
                .tag(3)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }

            ConnectionView()
                .tag(4)
                .tabItem {
                    Label("Bike", systemImage: "bicycle")
                }

            SettingsView()
                .tag(5)
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
        .onReceive(NotificationCenter.default.publisher(for: .switchToRideTab)) { _ in
            selectedTab = 0
            showSearch = false
        }
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

extension Notification.Name {
    static let switchToRideTab = Notification.Name("switchToRideTab")
}