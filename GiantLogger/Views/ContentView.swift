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
    @State private var gpxImportMessage: String?
    @State private var showGPXImportAlert = false
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

            ConnectionView()
                .tag(3)
                .tabItem {
                    Label("Bike", systemImage: "bicycle")
                }

            SettingsView()
                .tag(4)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .minimizeTabBarOnScrollDownIfAvailable()
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
        .onReceive(NotificationCenter.default.publisher(for: .switchToBikeTab)) { _ in
            selectedTab = 3
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
        .onReceive(NotificationCenter.default.publisher(for: .gpxImportResult)) { notification in
            guard let result = notification.object as? GPXImportResult else { return }
            if let name = result.routeName {
                gpxImportMessage = "Imported route: \(name)"
                selectedTab = 1
            } else {
                gpxImportMessage = result.error ?? "Import failed"
            }
            showGPXImportAlert = true
        }
        .alert("GPX Import", isPresented: $showGPXImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gpxImportMessage ?? "")
        }
    }
}

extension Notification.Name {
    static let switchToRideTab = Notification.Name("switchToRideTab")
    static let switchToHistoryTab = Notification.Name("switchToHistoryTab")
    static let switchToBikeTab = Notification.Name("switchToBikeTab")
    static let gpxImportResult = Notification.Name("gpxImportResult")
}

private extension View {
    @ViewBuilder
    func minimizeTabBarOnScrollDownIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
