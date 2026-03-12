import Foundation
import SwiftData
import Combine
import CoreLocation
import ActivityKit
import WidgetKit

/// Records ride telemetry + GPS samples and manages ride lifecycle.
@MainActor
class RideRecorder: ObservableObject {

    @Published var isRecording = false
    @Published var currentRide: Ride?
    @Published var sampleCount = 0
    @Published var elapsedSeconds: Int = 0
    @Published var heartRate: Double = 0

    var recordingInterval: TimeInterval = 2.0
    private let liveActivityManager = LiveActivityManager()
    var autoRecord: Bool {
        get { UserDefaults.standard.bool(forKey: "autoRecord") }
        set { UserDefaults.standard.set(newValue, forKey: "autoRecord") }
    }

    var logWorkouts: Bool {
        UserDefaults.standard.bool(forKey: "logWorkouts")
    }

    private var bikeService: GiantBikeService?
    private var locationManager: LocationManager?
    private var workoutManager: WorkoutManager?
    private var stravaService: StravaService?
    private var navigationEngine: NavigationEngine?
    private var modelContext: ModelContext?
    private var recordingTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var accumulatedDistance: Double = 0  // km
    private var lastSampleLocation: (lat: Double, lon: Double)?
    private var recordingStartDate: Date?
    private var movingSpeedSum: Double = 0
    private var movingSpeedCount: Int = 0
    private let watchConnectivity = WatchConnectivityManager.shared

    init() {
        UserDefaults.standard.register(defaults: ["autoRecord": true])
        liveActivityManager.cleanupStaleActivities()
    }

    func configure(bikeService: GiantBikeService, locationManager: LocationManager,
                   workoutManager: WorkoutManager, stravaService: StravaService,
                   navigationEngine: NavigationEngine, modelContext: ModelContext) {
        self.bikeService = bikeService
        self.locationManager = locationManager
        self.workoutManager = workoutManager
        self.stravaService = stravaService
        self.navigationEngine = navigationEngine
        self.modelContext = modelContext

        // Auto-start recording when GEV connects; always stop on disconnect
        bikeService.$isGevConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if connected && self.autoRecord && !self.isRecording {
                    self.startRecording()
                } else if !connected && self.isRecording {
                    self.stopRecording()
                }
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        guard !isRecording, let modelContext else { return }

        let ride = Ride()
        modelContext.insert(ride)
        currentRide = ride
        isRecording = true
        sampleCount = 0
        elapsedSeconds = 0
        accumulatedDistance = 0
        lastSampleLocation = nil
        recordingStartDate = Date()
        movingSpeedSum = 0
        movingSpeedCount = 0

        locationManager?.startTracking()
        if logWorkouts { workoutManager?.startWorkout() }
        liveActivityManager.startActivity()

        // Notify Watch that recording started
        watchConnectivity.sendTelemetry(
            speed: 0, battery: bikeService?.rideData.batteryPercent ?? 0,
            distance: 0, duration: 0, cadence: 0, watts: 0,
            isRecording: true, bikeName: SharedBikeData.bikeName
        )

        // Tick elapsed time every second
        durationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let start = recordingStartDate {
                    elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        }

        recordingTask = Task {
            while !Task.isCancelled {
                recordSample()
                try? await Task.sleep(for: .seconds(recordingInterval))
            }
        }
    }

    func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        durationTask?.cancel()
        durationTask = nil
        isRecording = false
        heartRate = 0
        liveActivityManager.endActivity()

        // End navigation if setting is enabled
        if UserDefaults.standard.bool(forKey: "endNavOnRideEnd") {
            navigationEngine?.stop()
        }

        // Notify Watch that recording stopped (both message + context)
        watchConnectivity.sendRecordingStop()
        watchConnectivity.sendTelemetry(
            speed: 0, battery: bikeService?.rideData.batteryPercent ?? 0,
            distance: accumulatedDistance, duration: elapsedSeconds,
            cadence: 0, watts: 0,
            isRecording: false, bikeName: SharedBikeData.bikeName
        )

        // Discard rides where user hasn't moved (< 10m) or has no samples
        if let ride = currentRide {
            ride.computeSummary()
            if (ride.samples ?? []).isEmpty || accumulatedDistance < 0.01 {
                modelContext?.delete(ride)
            } else {
                // Save workout to HealthKit if enabled
                if logWorkouts {
                    let hrSamples = (ride.samples ?? [])
                        .filter { $0.heartRate > 0 }
                        .map { (timestamp: $0.timestamp, bpm: $0.heartRate) }
                    workoutManager?.stopWorkout(
                        distance: ride.totalDistance,
                        elevationGain: ride.elevationGain,
                        avgPower: ride.avgPower,
                        duration: TimeInterval(ride.duration),
                        heartRateSamples: hrSamples
                    )
                }

                // Auto-upload to Strava if enabled
                if let strava = stravaService, strava.isConnected && strava.autoUpload {
                    let rideToUpload = ride
                    Task {
                        try? await strava.uploadRide(rideToUpload)
                    }
                }

                SharedBikeData.lastRideDate = ride.startDate
                SharedBikeData.lastRideDistance = ride.totalDistance
                SharedBikeData.lastRideDuration = TimeInterval(ride.duration)
                SharedBikeData.lastRideAvgSpeed = ride.avgSpeed
                SharedBikeData.lastRideElevationGain = ride.elevationGain
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        try? modelContext?.save()

        locationManager?.stopTracking()
        currentRide = nil
        recordingStartDate = nil
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func recordSample() {
        guard let bikeService, let currentRide, let modelContext else { return }

        // Skip recording until we have battery data (avoids 0% initial samples)
        if bikeService.batteryData == nil { return }

        let location = locationManager?.currentLocation
        let lat = location?.coordinate.latitude ?? 0
        let lon = location?.coordinate.longitude ?? 0

        // Accumulate GPS distance (Haversine)
        if let last = lastSampleLocation, lat != 0 || lon != 0 {
            let delta = Self.haversineDistance(
                lat1: last.lat, lon1: last.lon,
                lat2: lat, lon2: lon
            )
            if delta > 0.001 { // Ignore GPS jitter < 1m
                accumulatedDistance += delta
            }
        }
        if lat != 0 || lon != 0 {
            lastSampleLocation = (lat, lon)
        }

        // Update rideData distance and time from local tracking
        bikeService.rideData.distance = accumulatedDistance
        bikeService.rideData.rideTime = elapsedSeconds

        let sample = RideSample(
            rideData: bikeService.rideData,
            latitude: lat,
            longitude: lon,
            altitude: location?.altitude ?? 0,
            gpsSpeed: max(0, location?.speed ?? 0),
            course: max(0, location?.course ?? 0)
        )
        sample.ride = currentRide
        sample.heartRate = watchConnectivity.heartRate
        sample.packetLog = bikeService.getAndClearPacketBuffer()
        if currentRide.samples == nil { currentRide.samples = [] }
        currentRide.samples?.append(sample)
        modelContext.insert(sample)
        sampleCount += 1

        // Update heart rate from Watch
        heartRate = watchConnectivity.heartRate

        // Periodic save
        if sampleCount % 10 == 0 {
            try? modelContext.save()
        }

        // Feed GPS location to workout route builder
        if logWorkouts, let location {
            workoutManager?.addRouteLocation(location)
        }

        // Update turn-by-turn navigation with current position
        if let location, navigationEngine?.activeRoute != nil {
            navigationEngine?.updateLocation(location)
        }

        // Update running average speed (O(1) instead of O(n))
        if sample.speed > 0.5 {
            movingSpeedSum += sample.speed
            movingSpeedCount += 1
        }
        let avg = movingSpeedCount > 0 ? movingSpeedSum / Double(movingSpeedCount) : 0
        liveActivityManager.updateActivity(
            speed: bikeService.rideData.speed,
            distance: accumulatedDistance,
            elapsed: elapsedSeconds,
            battery: bikeService.rideData.batteryPercent,
            avgSpeed: avg,
            power: bikeService.rideData.watts
        )

        // Send telemetry to Apple Watch (including navigation state)
        let isNav = navigationEngine?.activeRoute != nil
        let navInstr = navigationEngine?.currentInstruction
        watchConnectivity.sendTelemetry(
            speed: bikeService.rideData.speed,
            battery: bikeService.rideData.batteryPercent,
            distance: accumulatedDistance,
            duration: elapsedSeconds,
            cadence: bikeService.rideData.cadence,
            watts: bikeService.rideData.watts,
            isRecording: true,
            bikeName: SharedBikeData.bikeName,
            isNavigating: isNav,
            navInstruction: navInstr?.maneuverType.rawValue ?? "",
            navDistance: navigationEngine?.distanceToNextManeuver ?? 0,
            navSymbol: navInstr?.maneuverType.sfSymbol ?? "arrow.up",
            navStreet: navInstr?.streetName
        )
    }

    /// Haversine distance in kilometers between two GPS coordinates.
    private static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0 // Earth radius in km
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}
