import Foundation
import Combine
import OSLog

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
    private var connectionTask: Task<Void, Never>?
    private var connectGEVAcked = false
    private let logger = Logger(subsystem: "dk.hilli.GiantLogger", category: "GEV")
    private let debugLog = DebugLogger.shared

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
        logger.info("BLE link up, sending connectGEV")
        debugLog.log("GEV", "BLE link up, sending connectGEV")
        connectGEVAcked = false
        sendConnect()

        connectionTask = Task {
            // Wait up to 5 seconds for connectGEV ACK (matching Android timeout)
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(100))
                if connectGEVAcked || Task.isCancelled { break }
            }

            guard !Task.isCancelled else { return }

            guard connectGEVAcked else {
                logger.error("connectGEV timeout — bike did not respond within 5s")
                debugLog.log("GEV", "ERROR: connectGEV timeout (5s) — no response from bike")
                return
            }

            isGevConnected = true
            debugLog.log("GEV", "GEV session established — requesting static data")

            // Request static info sequentially with delays
            requestFactoryData()
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            requestDiagnosticSyncDrive()
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            requestDiagnosticEnergyPak()
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            requestBattery()

            startPolling()
        }
    }

    private func onDisconnected() {
        logger.info("Disconnected from bike")
        debugLog.log("GEV", "Disconnected from bike")
        isGevConnected = false
        connectGEVAcked = false
        connectionTask?.cancel()
        connectionTask = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                requestRidingData()
                try? await Task.sleep(for: .milliseconds(300))
                requestBattery()
                try? await Task.sleep(for: .milliseconds(300))
                requestRemainingRange()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Notification Handling

    private func handleNotification(_ data: Data) {
        guard let plaintext = GiantProtocol.decodePacket(data) else {
            logger.warning("RX decode failed: len=\(data.count) hex=\(self.hexString(data), privacy: .public)")
            debugLog.log("GEV", "WARN: RX decode failed: len=\(data.count) hex=\(hexString(data))")
            return
        }

        let commandID = plaintext[0]
        let cmdHex = String(format: "0x%02X", commandID)
        logger.debug("RX cmd=0x\(String(commandID, radix: 16), privacy: .public)")
        debugLog.log("GEV", "RX cmd=\(cmdHex) plain=\(plaintext.map { String(format: "%02X", $0) }.joined())")

        switch commandID {
        case GiantProtocol.Command.connectGEV.rawValue:
            handleConnectGEVResponse(plaintext)

        case GiantProtocol.Command.readRidingData.rawValue:
            handleReadRidingData(plaintext)

        case GiantProtocol.Command.readRemainingRange.rawValue:
            handleReadRemainingRange(plaintext)

        case GiantProtocol.Command.readFactoryData.rawValue:
            handleReadFactoryData(plaintext)

        case GiantProtocol.Command.readBattery.rawValue:
            handleReadBattery(plaintext)

        case GiantProtocol.Command.diagnosticSyncDrive.rawValue:
            handleDiagnosticSyncDrive(plaintext)

        case GiantProtocol.Command.diagnosticEnergyPak.rawValue:
            handleDiagnosticEnergyPak(plaintext)

        default:
            logger.debug("Unhandled command id=0x\(String(commandID, radix: 16), privacy: .public)")
            debugLog.log("GEV", "Unhandled cmd=\(cmdHex)")
        }
    }

    private func handleConnectGEVResponse(_ plaintext: [UInt8]) {
        // Android verifies: decrypted[0] == 0x02 && decrypted[2] == 0x01
        if plaintext.count > 2 && plaintext[2] == 0x01 {
            connectGEVAcked = true
            logger.info("connectGEV ACK received — GEV session established")
            debugLog.log("GEV", "connectGEV ACK received — session established")
        } else {
            let statusByte = plaintext.count > 2 ? String(format: "0x%02X", plaintext[2]) : "N/A"
            logger.error("connectGEV rejected: status=\(statusByte, privacy: .public)")
            debugLog.log("GEV", "WARN: connectGEV rejected: status=\(statusByte)")
        }
    }

    private func handleReadRidingData(_ plaintext: [UInt8]) {
        guard let parsed = GiantProtocol.parseRidingData(plaintext) else { return }
        var updated = parsed
        updated.range = rideData.range
        rideData = updated
        logger.debug("Parsed riding data: speed=\(updated.speed) battery=\(updated.batteryPercent)")
        debugLog.log("GEV", "Riding: speed=\(updated.speed) battery=\(updated.batteryPercent)% cadence=\(updated.cadence) watts=\(updated.watts)")
    }

    private func handleReadRemainingRange(_ plaintext: [UInt8]) {
        guard let range = GiantProtocol.parseRemainingRange(plaintext) else { return }
        rideData.range = range
        logger.debug("Parsed remaining range: \(range)")
    }

    private func handleReadFactoryData(_ plaintext: [UInt8]) {
        factoryData = GiantProtocol.parseFactoryData(plaintext)
        logger.debug("Parsed factory data present=\(self.factoryData != nil)")
    }

    private func handleReadBattery(_ plaintext: [UInt8]) {
        batteryData = GiantProtocol.parseBatteryData(plaintext)
        guard let batteryData else {
            debugLog.log("GEV", "WARN: readBattery parse failed")
            return
        }
        rideData.batteryPercent = batteryData.capacityPercent
        logger.debug(
            "Parsed battery data: capacity=\(batteryData.capacityPercent) life=\(batteryData.lifePercent)"
        )
        debugLog.log("GEV", "Battery: capacity=\(batteryData.capacityPercent)% life=\(batteryData.lifePercent)%")
    }

    private func handleDiagnosticSyncDrive(_ plaintext: [UInt8]) {
        syncDriveData = GiantProtocol.parseDiagnosticSyncDrive(plaintext)
        logger.debug("Parsed SyncDrive data present=\(self.syncDriveData != nil)")
    }

    private func handleDiagnosticEnergyPak(_ plaintext: [UInt8]) {
        energyPakData = GiantProtocol.parseDiagnosticEnergyPak(plaintext)
        logger.debug("Parsed EnergyPak data present=\(self.energyPakData != nil)")
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
