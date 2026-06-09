import Foundation
import SwiftData
import Combine
import CoreLocation
import MapKit
import ActivityKit
import WidgetKit
import UserNotifications
import UIKit
import OSLog

// swiftlint:disable file_length

/// Records ride telemetry + GPS samples and manages ride lifecycle.
@MainActor
// swiftlint:disable:next type_body_length
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
    private let debugLog = DebugLogger.shared
    private let logger = Logger(subsystem: "dk.hilli.GiantLogger", category: "Recorder")

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

        requestNotificationPermission()

        // Auto-start recording when GEV connects; always stop on disconnect
        bikeService.$isGevConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if connected && self.autoRecord && !self.isRecording {
                    self.debugLog.log("Recorder", "Auto-record triggered by GEV connect")
                    self.startRecording()
                } else if !connected && self.isRecording {
                    self.debugLog.log("Recorder", "Auto-stop triggered by GEV disconnect")
                    self.stopRecording()
                }
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        if isRecording {
            debugLog.log("Recorder", "startRecording skipped — already recording")
            return
        }
        guard let modelContext else {
            logger.warning("startRecording failed — modelContext is nil (services not configured?)")
            debugLog.log("Recorder", "WARN: startRecording failed — modelContext nil")
            return
        }

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

        debugLog.log("Recorder", "Recording started")
        postBackgroundNotification(
            title: "Ride Recording Started",
            body: "Connected to \(SharedBikeData.bikeName) — recording GPS and telemetry."
        )

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
        let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "stop-recording") {
            Task { @MainActor in
                self.debugLog.log("Recorder", "WARN: background task expired while stopping recording")
            }
        }
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        recordingTask?.cancel()
        recordingTask = nil
        durationTask?.cancel()
        durationTask = nil
        isRecording = false
        heartRate = 0
        liveActivityManager.endActivity()
        let stopDate = Date()

        let distKm = String(format: "%.2f", accumulatedDistance)
        debugLog.log("Recorder", "Recording stopped — \(sampleCount) samples, \(distKm) km")

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

        // Discard rides with no samples, no meaningful movement, or no GPS data
        if let ride = currentRide {
            ride.computeSummary()
            let samples = ride.samples ?? []
            let hasGPS = samples.contains { $0.latitude != 0 || $0.longitude != 0 }
            let shouldDiscard = samples.isEmpty
                || accumulatedDistance < 0.01
                || !hasGPS
            if shouldDiscard {
                debugLog.log("Recorder", "Discarding ride: \(samples.count) samples, \(String(format: "%.3f", accumulatedDistance)) km, gps=\(hasGPS)")
                if logWorkouts { workoutManager?.discardWorkout() }
                modelContext?.delete(ride)
            } else {
                // Save workout to HealthKit if enabled
                if logWorkouts {
                    let watchHRSamples = watchConnectivity
                        .heartRateSamples(since: recordingStartDate, through: stopDate)
                        .map { (timestamp: $0.timestamp, bpm: $0.bpm) }
                    let hrSamples = watchHRSamples.isEmpty
                        ? (ride.samples ?? [])
                            .filter { $0.heartRate > 0 }
                            .map { (timestamp: $0.timestamp, bpm: $0.heartRate) }
                        : watchHRSamples
                    // Compute average rider power (human pedalling effort)
                    let riderPowerSamples = (ride.samples ?? []).filter { $0.torque > 0 && $0.cadence > 0 }
                    let avgRiderPower = riderPowerSamples.isEmpty ? 0.0 :
                        riderPowerSamples.map { $0.torque * $0.cadence * 0.10472 }.reduce(0, +)
                            / Double(riderPowerSamples.count)
                    workoutManager?.stopWorkout(
                        distance: ride.totalDistance,
                        elevationGain: ride.elevationGain,
                        avgMotorPower: ride.avgPower,
                        avgRiderPower: avgRiderPower,
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

                // Reverse-geocode start/end to generate a ride name
                resolveRideName(for: ride, samples: samples)
            }
        }
        try? modelContext?.save()

        // Notify user if app is in background
        let distStr = String(format: "%.1f km", accumulatedDistance)
        let mins = elapsedSeconds / 60
        postBackgroundNotification(
            title: "Ride Recording Stopped",
            body: "Recorded \(distStr) in \(mins) min."
        )

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

    // swiftlint:disable:next function_body_length
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
        sample.horizontalAccuracy = (lat != 0 || lon != 0) ? (location?.horizontalAccuracy ?? -1) : -1
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
            power: bikeService.rideData.motorWatts
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
            watts: bikeService.rideData.motorWatts,
            isRecording: true,
            bikeName: SharedBikeData.bikeName,
            isNavigating: isNav,
            navInstruction: navInstr?.maneuverType.rawValue ?? "",
            navDistance: navigationEngine?.distanceToNextManeuver ?? 0,
            navSymbol: navInstr?.maneuverType.sfSymbol ?? "arrow.up",
            navStreet: navInstr?.streetName
         )
    }
}

// MARK: - Background Notifications

extension RideRecorder {

    /// Request notification permission (called once during configure).
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a local notification only when the app is in the background.
    func postBackgroundNotification(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ride-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Haversine distance in kilometers between two GPS coordinates.
    static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadius = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let sinHalf = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        let arc = 2 * atan2(sqrt(sinHalf), sqrt(1 - sinHalf))
        return earthRadius * arc
    }
}

// MARK: - Ride Naming (Reverse Geocoding)

extension RideRecorder {

    /// Resolve a human-readable ride name from start/end GPS coordinates.
    /// Falls back to "Giant eBike Ride" on failure or missing data.
    /// Uses a background task to ensure geocoding completes even when
    /// the app is suspended (e.g. phone in pocket).
    func resolveRideName(for ride: Ride, samples: [RideSample]) {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let gpsSamples = sorted.filter { $0.latitude != 0 || $0.longitude != 0 }
        guard !gpsSamples.isEmpty else {
            ride.name = "Giant eBike Ride"
            try? modelContext?.save()
            return
        }

        // Set fallback immediately so the ride is never unnamed
        ride.name = "Giant eBike Ride"
        try? modelContext?.save()

        // Pick a small window of the most reliable fixes at each end rather than
        // a single first/last point. A lone cold-start (start) or GPS-dropout
        // (end) fix often snaps to the wrong nearby street; voting across a few
        // accurate fixes is far more robust.
        let startCandidates = Self.namingCandidates(from: gpsSamples, fromStart: true)
        let endCandidates = Self.namingCandidates(from: gpsSamples, fromStart: false)

        // Request background execution time for the network call
        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "geocode-ride") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

        Task {
            let startName = await reverseGeocodeConsensus(samples: startCandidates)
            let endName = await reverseGeocodeConsensus(samples: endCandidates)

            await MainActor.run {
                if let start = startName, let end = endName, start != end {
                    ride.name = "\(start) → \(end)"
                } else if let start = startName {
                    ride.name = start
                } else if let end = endName {
                    ride.name = end
                }
                debugLog.log("Recorder", "Ride named: \(ride.name)")
                try? modelContext?.save()

                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }

    /// Select up to 3 reliable fixes at the start or end of a ride for naming.
    /// Prefers fixes accurate to within 50 m; falls back to raw endpoints when
    /// no accuracy data is available (e.g. legacy rides) or none qualify.
    private static func namingCandidates(from gpsSamples: [RideSample], fromStart: Bool) -> [RideSample] {
        let maxCandidates = 3
        let accuracyThreshold = 50.0
        let accurate = gpsSamples.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= accuracyThreshold }
        let pool = accurate.isEmpty ? gpsSamples : accurate
        guard !pool.isEmpty else { return [] }
        return fromStart
            ? Array(pool.prefix(maxCandidates))
            : Array(pool.suffix(maxCandidates))
    }

    /// Reverse-geocode several nearby fixes and return the most frequently
    /// resolved place name, which is more robust than trusting one coordinate.
    private func reverseGeocodeConsensus(samples: [RideSample]) async -> String? {
        var tally: [String: Int] = [:]
        var order: [String] = []
        for sample in samples {
            let loc = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            if let name = await reverseGeocode(location: loc) {
                if tally[name] == nil { order.append(name) }
                tally[name, default: 0] += 1
            }
        }
        // Most frequent name wins; ties broken by earliest occurrence.
        var best: String?
        var bestCount = 0
        for name in order where (tally[name] ?? 0) > bestCount {
            best = name
            bestCount = tally[name] ?? 0
        }
        return best
    }

    /// Reverse-geocode a location into a short place name (street or locality).
    private func reverseGeocode(location: CLLocation) async -> String? {
        do {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            let mapItems = try await request.mapItems
            guard let item = mapItems.first else { return nil }
            return item.addressRepresentations?.cityName
                ?? item.addressRepresentations?.cityWithContext
                ?? item.address?.shortAddress
                ?? item.name
        } catch {
            debugLog.log("Recorder", "Geocode error: \(error.localizedDescription)")
            return nil
        }
    }
}
