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
    private var packetBuffer: [String] = []

    func getAndClearPacketBuffer() -> String {
        let log = packetBuffer.joined(separator: "\n")
        packetBuffer.removeAll()
        return log
    }

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
        let data = GiantProtocol.connectCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func sendDisconnect() {
        let data = GiantProtocol.disconnectCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func requestRidingData() {
        let data = GiantProtocol.readRidingDataCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func requestFactoryData() {
        let data = GiantProtocol.readFactoryDataCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func requestBattery() {
        let data = GiantProtocol.readBatteryCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func requestRemainingRange() {
        let data = GiantProtocol.readRemainingRangeCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func requestDiagnosticSyncDrive() {
        let data = GiantProtocol.diagnosticSyncDriveCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func requestDiagnosticEnergyPak() {
        let data = GiantProtocol.diagnosticEnergyPakCommand()
        logTX(data)
        bikeManager?.write(data)
    }

    func toggleLight() {
        let data = GiantProtocol.triggerLightCommand()
        debugLog.log("GEV", "TRIGGER light → \(data.count)B")
        logTX(data)
        sendTrigger(data)
    }

    func assistUp() {
        let data = GiantProtocol.triggerAssistUpCommand()
        debugLog.log("GEV", "TRIGGER assistUp → \(data.count)B")
        logTX(data)
        sendTrigger(data)
    }

    func assistDown() {
        let data = GiantProtocol.triggerAssistDownCommand()
        debugLog.log("GEV", "TRIGGER assistDown → \(data.count)B")
        logTX(data)
        sendTrigger(data)
    }

    func togglePower() {
        let data = GiantProtocol.triggerPowerCommand()
        debugLog.log("GEV", "TRIGGER power → \(data.count)B")
        logTX(data)
        sendTrigger(data)
    }

    /// Send a trigger command: pause polling, write without BLE-level ACK
    /// (matching Android's sendCommandWithoutResponse), then resume polling.
    private func sendTrigger(_ data: Data) {
        // Pause polling so the trigger isn't queued behind a polling write
        pollingTask?.cancel()
        pollingTask = nil

        // Fire-and-forget write (Android uses WRITE_TYPE_NO_RESPONSE for triggers)
        bikeManager?.writeWithoutResponse(data)

        // Resume polling after a brief delay
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            startPolling()
        }
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
                requestDiagnosticSyncDrive()  // 0x16 — live motor telemetry (always responds)
                try? await Task.sleep(for: .milliseconds(300))
                requestBattery()              // 0x13 — battery status (always responds)
                try? await Task.sleep(for: .milliseconds(300))
                requestRidingData()           // 0x1B — distance/time/watts (only while riding)
                try? await Task.sleep(for: .milliseconds(300))
                requestRemainingRange()       // 0x1D — range estimate (only while riding)
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
        packetBuffer.append("RX \(cmdHex) \(hexString(data))")

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
        var factory = GiantProtocol.parseFactoryData(plaintext)
        // Frame number bytes are often zeros; use BLE device name instead (e.g., "GCHA12354")
        if let name = bikeManager?.connectedPeripheralName {
            factory?.frameNumber = name
        }
        factoryData = factory
        if let f = factory {
            debugLog.log("GEV", "Factory: speedLimit=\(f.speedLimitation) circ=\(f.circumference)mm frame=\(f.frameNumber) cat=\(f.evCategory) rcHW=\(f.rcHardwareVersion)")
        }
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
        guard let parsed = GiantProtocol.parseDiagnosticSyncDrive(plaintext) else { return }
        syncDriveData = parsed
        // Map live motor telemetry into rideData for dashboard display
        rideData.speed = parsed.speed
        rideData.torque = parsed.torque
        rideData.cadence = parsed.cadence
        rideData.assistCurrent = parsed.assistCurrent
        rideData.lightMode = parsed.lightMode
        if parsed.errorCode != 0 {
            rideData.errorCode = parsed.errorCode
        }
        logger.debug("SyncDrive: speed=\(parsed.speed) torque=\(parsed.torque) cadence=\(parsed.cadence) current=\(parsed.assistCurrent)A light=\(parsed.lightMode)")
        debugLog.log("GEV", "SyncDrive: speed=\(parsed.speed) torque=\(parsed.torque) cadence=\(parsed.cadence) acur=\(parsed.assistCurrent)A light=\(parsed.lightMode)")
    }

    private func handleDiagnosticEnergyPak(_ plaintext: [UInt8]) {
        energyPakData = GiantProtocol.parseDiagnosticEnergyPak(plaintext)
        if let ep = energyPakData {
            logger.debug("EnergyPak: ecode=\(ep.errorCode) alarm=\(ep.alarm) uv=\(ep.underVoltageAlarm)")
            debugLog.log("GEV", "EnergyPak: ecode=\(ep.errorCode) alarm=\(ep.alarm) uv=\(ep.underVoltageAlarm)")
        }
    }

    private func logTX(_ data: Data) {
        packetBuffer.append("TX \(hexString(data))")
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
