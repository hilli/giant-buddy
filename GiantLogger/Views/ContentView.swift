import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var bikeService: GiantBikeService
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var rideRecorder: RideRecorder
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var crashDetector: CrashDetector
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var navigationEngine: NavigationEngine
    @State private var showSearch = false
    @State private var selectedTab = 0
    @AppStorage("crashDetectionEnabled") private var crashDetectionEnabled = false

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
        .fullScreenCover(isPresented: $crashDetector.isCrashDetected) {
            CrashAlertView(crashDetector: crashDetector, location: locationManager.currentLocation)
        }
        .tint(.accentColor)
        .onReceive(NotificationCenter.default.publisher(for: .switchToRideTab)) { _ in
            selectedTab = 0
            showSearch = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToHistoryTab)) { _ in
            selectedTab = 2
        }
        .onChange(of: rideRecorder.isRecording) { _, isRecording in
            let enabled = UserDefaults.standard.bool(forKey: "crashDetectionEnabled")
            if isRecording && enabled {
                crashDetector.startMonitoring()
            } else {
                crashDetector.stopMonitoring()
            }
        }
        .onChange(of: crashDetectionEnabled) { _, enabled in
            if rideRecorder.isRecording {
                if enabled {
                    crashDetector.startMonitoring()
                } else {
                    crashDetector.stopMonitoring()
                }
            }
        }
    }
}

extension Notification.Name {
    static let switchToRideTab = Notification.Name("switchToRideTab")
    static let switchToHistoryTab = Notification.Name("switchToHistoryTab")
}
