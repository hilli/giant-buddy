import Foundation
import SwiftData
import Combine

/// Records ride telemetry + GPS samples and manages ride lifecycle.
@MainActor
class RideRecorder: ObservableObject {

    @Published var isRecording = false
    @Published var currentRide: Ride?
    @Published var sampleCount = 0

    var recordingInterval: TimeInterval = 2.0
    var autoRecord = true

    private var bikeService: GiantBikeService?
    private var locationManager: LocationManager?
    private var modelContext: ModelContext?
    private var recordingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func configure(bikeService: GiantBikeService, locationManager: LocationManager, modelContext: ModelContext) {
        self.bikeService = bikeService
        self.locationManager = locationManager
        self.modelContext = modelContext

        // Auto-start recording when GEV connects
        bikeService.$isGevConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self, self.autoRecord else { return }
                if connected && !self.isRecording {
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

        locationManager?.startTracking()

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
        isRecording = false

        currentRide?.computeSummary()
        try? modelContext?.save()

        locationManager?.stopTracking()
        currentRide = nil
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

        let location = locationManager?.currentLocation
        let sample = RideSample(
            rideData: bikeService.rideData,
            latitude: location?.coordinate.latitude ?? 0,
            longitude: location?.coordinate.longitude ?? 0,
            altitude: location?.altitude ?? 0,
            gpsSpeed: max(0, location?.speed ?? 0),
            course: max(0, location?.course ?? 0)
        )
        sample.ride = currentRide
        currentRide.samples.append(sample)
        modelContext.insert(sample)
        sampleCount += 1

        // Periodic save
        if sampleCount % 10 == 0 {
            try? modelContext.save()
        }
    }
}
