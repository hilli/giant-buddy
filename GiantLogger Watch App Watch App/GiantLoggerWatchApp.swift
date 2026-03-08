import SwiftUI

@main
struct GiantLoggerWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(sessionManager)
        }
    }
}
