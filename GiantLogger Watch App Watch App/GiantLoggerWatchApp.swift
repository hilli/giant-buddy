import SwiftUI
import WidgetKit

@main
struct GiantLoggerWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(sessionManager)
                .onAppear {
                    sessionManager.requestHealthKitPermissions()
                }
        }
    }
}
