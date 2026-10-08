#if DEBUG
    import Foundation

    extension WatchSessionManager {
        /// Seeds demo values for App Store screenshots when launched with
        /// `-ScreenshotMode YES`. Mirrors the iPhone `ScreenshotMode` demo ride.
        /// Returns `true` when demo mode is active so WatchConnectivity is skipped.
        func seedScreenshotDataIfRequested() -> Bool {
            guard UserDefaults.standard.bool(forKey: "ScreenshotMode") else { return false }
            bikeName = "Trance X E+"
            speed = 24.8
            battery = 76
            distance = 18.4
            duration = 2650
            cadence = 78
            watts = 180
            isRecording = true
            estimatedRange = 62
            totalOdometer = 2140
            totalUsageHours = 118
            heartRate = 142
            activeCalories = 412
            isNavigating = true
            navInstruction = "Turn right"
            navDistance = 350
            navSymbol = "arrow.turn.up.right"
            navStreet = "Strandvejen"
            isPhoneReachable = true
            return true
        }
    }
#endif
