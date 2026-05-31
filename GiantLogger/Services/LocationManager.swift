import Foundation
import CoreLocation
import os

/// CoreLocation wrapper for GPS tracking during rides.
@MainActor
class LocationManager: NSObject, ObservableObject {

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false

    private let manager = CLLocationManager()
    private let debugLog = DebugLogger.shared

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3 // meters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    /// True when the app can receive GPS in the background.
    var hasAlwaysAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    func startTracking() {
        guard !isTracking else { return }
        if authorizationStatus == .notDetermined {
            requestPermission()
        } else if authorizationStatus == .authorizedWhenInUse {
            // Attempt upgrade to "Always" for background recording
            manager.requestAlwaysAuthorization()
        }
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    /// Request a single location fix (e.g. for weather). Does not start continuous tracking.
    func requestSingleLocation() {
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        manager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Reject invalid (negative accuracy), very poor (>100m), or stale
        // (cached pre-tracking) fixes so downstream consumers — ride naming,
        // distance accumulation, navigation — never see bogus coordinates.
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        Task { @MainActor in
            currentLocation = location
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            debugLog.log("Location", "Authorization changed: \(status.debugDescription)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            debugLog.log("Location", "Error: \(error.localizedDescription)")
        }
    }
}

extension CLAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedWhenInUse: return "whenInUse"
        case .authorizedAlways: return "always"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
