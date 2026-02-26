import Foundation
import Combine

/// High-level interface to the Giant e-bike. Sends commands, parses responses,
/// and publishes live telemetry data.
@MainActor
class GiantBikeService: ObservableObject {

    @Published var rideData = RideData()
    @Published var factoryData: FactoryData?
    @Published var batteryData: BatteryData?
    @Published var syncDriveData: SyncDriveData?
    @Published var energyPakData: EnergyPakData?
    @Published var isGevConnected = false

    private var bikeManager: BikeManager?
    private var cancellables = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?

    func attach(to bikeManager: BikeManager) {
        self.bikeManager = bikeManager

        bikeManager.notificationReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleNotification(data)
            }
            .store(in: &cancellables)

        bikeManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .connected {
                    self?.onConnected()
                } else if state == .disconnected {
                    self?.onDisconnected()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Commands

    func sendConnect() {
        bikeManager?.write(GiantProtocol.connectCommand())
    }

    func sendDisconnect() {
        bikeManager?.write(GiantProtocol.disconnectCommand())
    }

    func requestRidingData() {
        bikeManager?.write(GiantProtocol.readRidingDataCommand())
    }

    func requestFactoryData() {
        bikeManager?.write(GiantProtocol.readFactoryDataCommand())
    }

    func requestBattery() {
        bikeManager?.write(GiantProtocol.readBatteryCommand())
    }

    func requestRemainingRange() {
        bikeManager?.write(GiantProtocol.readRemainingRangeCommand())
    }

    func requestDiagnosticSyncDrive() {
        bikeManager?.write(GiantProtocol.diagnosticSyncDriveCommand())
    }

    func requestDiagnosticEnergyPak() {
        bikeManager?.write(GiantProtocol.diagnosticEnergyPakCommand())
    }

    func toggleLight() {
        bikeManager?.write(GiantProtocol.triggerLightCommand())
    }

    func assistUp() {
        bikeManager?.write(GiantProtocol.triggerAssistUpCommand())
    }

    func assistDown() {
        bikeManager?.write(GiantProtocol.triggerAssistDownCommand())
    }

    func togglePower() {
        bikeManager?.write(GiantProtocol.triggerPowerCommand())
    }

    // MARK: - Lifecycle

    private func onConnected() {
        sendConnect()
        isGevConnected = true

        // Request static info once
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            requestFactoryData()
            try? await Task.sleep(for: .milliseconds(300))
            requestDiagnosticSyncDrive()
            try? await Task.sleep(for: .milliseconds(300))
            requestDiagnosticEnergyPak()
        }

        startPolling()
    }

    private func onDisconnected() {
        isGevConnected = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                requestRidingData()
                try? await Task.sleep(for: .seconds(2))
                requestRemainingRange()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Notification Handling

    private func handleNotification(_ data: Data) {
        guard let plaintext = GiantProtocol.decodePacket(data) else { return }

        let commandID = plaintext[0]

        switch commandID {
        case GiantProtocol.Command.readRidingData.rawValue:
            if let parsed = GiantProtocol.parseRidingData(plaintext) {
                // Preserve range from separate command
                var updated = parsed
                updated.range = rideData.range
                rideData = updated
            }

        case GiantProtocol.Command.readRemainingRange.rawValue:
            if let range = GiantProtocol.parseRemainingRange(plaintext) {
                rideData.range = range
            }

        case GiantProtocol.Command.readFactoryData.rawValue:
            factoryData = GiantProtocol.parseFactoryData(plaintext)

        case GiantProtocol.Command.readBattery.rawValue:
            batteryData = GiantProtocol.parseBatteryData(plaintext)

        case GiantProtocol.Command.diagnosticSyncDrive.rawValue:
            syncDriveData = GiantProtocol.parseDiagnosticSyncDrive(plaintext)

        case GiantProtocol.Command.diagnosticEnergyPak.rawValue:
            energyPakData = GiantProtocol.parseDiagnosticEnergyPak(plaintext)

        default:
            break
        }
    }
}
