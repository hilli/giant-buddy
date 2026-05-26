@preconcurrency import ActivityKit
import Foundation
import OSLog

/// Manages the Live Activity lifecycle for ride recording.
@MainActor
class LiveActivityManager: ObservableObject {

    @Published var isActivityActive = false

    private var currentActivity: Activity<RideActivityAttributes>?
    private let logger = Logger(subsystem: "dk.hilli.GiantLogger", category: "LiveActivity")

    func cleanupStaleActivities() {
        Task { @MainActor in
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    func startActivity() {
        cleanupStaleActivities()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities are disabled by the user")
            return
        }

        let initialState = RideActivityAttributes.ContentState(
            speed: 0,
            distance: 0,
            elapsedSeconds: 0,
            batteryPercent: 0,
            avgSpeed: 0,
            power: 0
        )

        let attributes = RideActivityAttributes()

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            logger.info("Started Live Activity: \(activity.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func updateActivity(speed: Double, distance: Double, elapsed: Int,
                        battery: Int, avgSpeed: Double, power: Double) {
        guard currentActivity != nil else { return }

        let state = RideActivityAttributes.ContentState(
            speed: speed,
            distance: distance,
            elapsedSeconds: elapsed,
            batteryPercent: battery,
            avgSpeed: avgSpeed,
            power: power
        )

        Task { @MainActor in
            await currentActivity?.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity() {
        guard currentActivity != nil else { return }
        isActivityActive = false

        Task { @MainActor in
            guard let activity = currentActivity else { return }
            let finalState = activity.content.state
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            logger.info("Ended Live Activity: \(activity.id)")
            currentActivity = nil
        }
    }
}
