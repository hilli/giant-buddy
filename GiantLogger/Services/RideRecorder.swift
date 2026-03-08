import Foundation
import SwiftData
import Combine
import CoreLocation
import ActivityKit

/// Records ride telemetry + GPS samples and manages ride lifecycle.
@MainActor
class RideRecorder: ObservableObject {

    @Published var isRecording = false
    @Published var currentRide: Ride?
    @Published var sampleCount = 0
    @Published var elapsedSeconds: Int = 0

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
    private var modelContext: ModelContext?
    private var recordingTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var accumulatedDistance: Double = 0  // km
    private var lastSampleLocation: (lat: Double, lon: Double)?
    private var recordingStartDate: Date?
    private var movingSpeedSum: Double = 0
    private var movingSpeedCount: Int = 0

    init() {
        UserDefaults.standard.register(defaults: ["autoRecord": true])
    }

    func configure(bikeService: GiantBikeService, locationManager: LocationManager,
                   workoutManager: WorkoutManager, stravaService: StravaService,
                   modelContext: ModelContext) {
        self.bikeService = bikeService
        self.locationManager = locationManager
        self.workoutManager = workoutManager
        self.stravaService = stravaService
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
        liveActivityManager.endActivity()

        // Discard rides where user hasn't moved (< 10m) or has no samples
        if let ride = currentRide {
            ride.computeSummary()
            if (ride.samples ?? []).isEmpty || accumulatedDistance < 0.01 {
                modelContext?.delete(ride)
            } else {
                // Save workout to HealthKit if enabled
                if logWorkouts {
                    workoutManager?.stopWorkout(
                        distance: ride.totalDistance,
                        elevationGain: ride.elevationGain,
                        avgPower: ride.avgPower,
                        duration: TimeInterval(ride.duration)
                    )
                }

                // Auto-upload to Strava if enabled
                if let strava = stravaService, strava.isConnected && strava.autoUpload {
                    let rideToUpload = ride
                    Task {
                        try? await strava.uploadRide(rideToUpload)
                    }
                }
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
        sample.packetLog = bikeService.getAndClearPacketBuffer()
        if currentRide.samples == nil { currentRide.samples = [] }
        currentRide.samples?.append(sample)
        modelContext.insert(sample)
        sampleCount += 1

        // Periodic save
        if sampleCount % 10 == 0 {
            try? modelContext.save()
        }

        // Feed GPS location to workout route builder
        if logWorkouts, let location {
            workoutManager?.addRouteLocation(location)
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
