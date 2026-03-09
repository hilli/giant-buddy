import Foundation
import Combine
import OSLog
import SwiftData
import WidgetKit

/// High-level interface to the Giant e-bike. Sends commands, parses responses,
/// and publishes live telemetry data.
@MainActor
class GiantBikeService: ObservableObject {

    @Published var rideData = RideData()
    @Published var factoryData: FactoryData?
    @Published var batteryData: BatteryData?
    @Published var syncDriveData: SyncDriveData?
    @Published var energyPakData: EnergyPakData?
    @Published var bikeInfo: BikeInfo?
    @Published var isGevConnected = false
    @Published var isFetchingBikeInfo = false

    private var bikeManager: BikeManager?
    private var cancellables = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var connectGEVAcked = false
    private let logger = Logger(subsystem: "dk.hilli.GiantLogger", category: "GEV")
    private let debugLog = DebugLogger.shared
    private var rangeTxCount = 0
    private var rangeRxCount = 0
    private var packetBuffer: [String] = []
    /// Track which bike data commands have been processed (first-response wins)
    private var processedBikeDataCmds = Set<UInt8>()

    /// SwiftData context for inserting battery snapshots and error log entries
    var modelContext: ModelContext?

    init() {
        // Restore last known battery % so dashboard shows it when not connected
        let saved = UserDefaults.standard.integer(forKey: "lastBatteryPercent")
        if saved > 0 { rideData.batteryPercent = saved }
        // Restore last known range (eco)
        let savedRange = UserDefaults.standard.integer(forKey: "lastRangeKm")
        if savedRange > 0 {
            rideData.rangeData = RemainingRangeData(eco: savedRange, normal: 0, power: 0, boost: 0, smart: 0)
        }
        // Restore cached bike info
        if let data = UserDefaults.standard.data(forKey: "cachedBikeInfo"),
           let cached = try? JSONDecoder().decode(BikeInfo.self, from: data) {
            bikeInfo = cached
        }
        // Restore cached factory data
        if let data = UserDefaults.standard.data(forKey: "cachedFactoryData"),
           let cached = try? JSONDecoder().decode(FactoryData.self, from: data) {
            factoryData = cached
        }
    }

    private func saveBikeInfo() {
        if let data = try? JSONEncoder().encode(bikeInfo) {
            UserDefaults.standard.set(data, forKey: "cachedBikeInfo")
        }
    }

    private func saveFactoryData() {
        if let data = try? JSONEncoder().encode(factoryData) {
            UserDefaults.standard.set(data, forKey: "cachedFactoryData")
        }
    }

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
        let data = GiantProtocol.readBikeDataRideControlCommand()
        rangeTxCount += 1
        debugLog.log("GEV", "TX range cmd=0x11 (#\(rangeTxCount), rxCount=\(rangeRxCount))")
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

    /// Fetch all bike data commands (0x05-0x13) sequentially with delays
    func fetchAllBikeData() {
        guard isGevConnected else { return }
        isFetchingBikeInfo = true
        processedBikeDataCmds.removeAll()
        if bikeInfo == nil { bikeInfo = BikeInfo() }

        Task {
            for cmd in GiantProtocol.allBikeDataCommands {
                guard !Task.isCancelled else { break }
                let data = GiantProtocol.readSingleBikeDataCommand(cmd)
                let cmdHex = String(format: "0x%02X", cmd.rawValue)
                debugLog.log("GEV", "TX bikeData cmd=\(cmdHex)")
                logTX(data)
                bikeManager?.write(data)
                try? await Task.sleep(for: .milliseconds(400))
            }
            bikeInfo?.lastUpdated = Date()
            saveBikeInfo()
            recordBatterySnapshotIfNeeded()
            recordErrorCodesIfNeeded()
            if let info = bikeInfo {
                SharedBikeData.batteryPercent = info.epCapacityPercent
                SharedBikeData.batteryHealth = info.epLifePercent
                SharedBikeData.totalOdometer = Double(info.odo)
                SharedBikeData.lastConnected = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
            isFetchingBikeInfo = false
            debugLog.log("GEV", "Bike data fetch complete")
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

            // Fetch full bike info (all passive + active data commands)
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            fetchAllBikeData()

            // Wait for bike data fetch to complete before starting polling
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }

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
                requestRemainingRange()       // 0x11 — range per assist mode
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

        case GiantProtocol.Command.bikeDataRideControl.rawValue:
            handleRemainingRange(plaintext)

        case GiantProtocol.Command.readFactoryData.rawValue:
            handleReadFactoryData(plaintext)

        case GiantProtocol.Command.readBattery.rawValue:
            handleReadBattery(plaintext)

        case GiantProtocol.Command.diagnosticSyncDrive.rawValue:
            handleDiagnosticSyncDrive(plaintext)

        case GiantProtocol.Command.diagnosticEnergyPak.rawValue:
            handleDiagnosticEnergyPak(plaintext)

        case GiantProtocol.Command.passiveRC1.rawValue:
            handleBikeInfoResponse(plaintext, label: "RC version")
        case GiantProtocol.Command.passiveRC2.rawValue:
            handleBikeInfoResponse(plaintext, label: "Mode usage")
        case GiantProtocol.Command.passiveRC3.rawValue,
             GiantProtocol.Command.passiveRC4.rawValue:
            handleBikeInfoResponse(plaintext, label: "RC error")
        case GiantProtocol.Command.passiveSD1.rawValue:
            handleBikeInfoResponse(plaintext, label: "Motor info")
        case GiantProtocol.Command.passiveSD2.rawValue:
            handleBikeInfoResponse(plaintext, label: "Service data")
        case GiantProtocol.Command.passiveSD3.rawValue,
             GiantProtocol.Command.passiveSD4.rawValue:
            handleBikeInfoResponse(plaintext, label: "Motor error")
        case GiantProtocol.Command.passiveEP1.rawValue:
            handleBikeInfoResponse(plaintext, label: "EP version")
        case GiantProtocol.Command.passiveEP2.rawValue:
            handleBikeInfoResponse(plaintext, label: "EP charge")
        case GiantProtocol.Command.passiveEP3.rawValue:
            handleBikeInfoResponse(plaintext, label: "EP error")
        case GiantProtocol.Command.passiveEP4.rawValue:
            handleBikeInfoResponse(plaintext, label: "EP capacity")
        case GiantProtocol.Command.activeSyncDrive.rawValue:
            handleBikeInfoResponse(plaintext, label: "ODO")

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
        updated.rangeData = rideData.rangeData
        rideData = updated
        logger.debug("Parsed riding data: speed=\(updated.speed) battery=\(updated.batteryPercent)")
        debugLog.log("GEV", "Riding: speed=\(updated.speed) battery=\(updated.batteryPercent)% cadence=\(updated.cadence) watts=\(updated.watts)")
    }

    private func handleRemainingRange(_ plaintext: [UInt8]) {
        rangeRxCount += 1
        let rawBytes = plaintext.map { String(format: "%02X", $0) }.joined()
        debugLog.log("GEV", "RX range raw=\(rawBytes) (#\(rangeRxCount)/\(rangeTxCount) TX)")
        guard let rangeData = GiantProtocol.parseRemainingRange(plaintext) else {
            debugLog.log("GEV", "WARN: range parse failed")
            return
        }
        // Bike sends 2 responses per request: first has real data, second is all zeros.
        // Only accept responses with at least one non-zero mode.
        guard !rangeData.nonZeroModes.isEmpty else {
            debugLog.log("GEV", "Range: all zeros — ignoring (kept previous)")
            return
        }
        rideData.rangeData = rangeData
        UserDefaults.standard.set(rangeData.eco, forKey: "lastRangeKm")
        // Share best available range with widgets
        let bestRange = rangeData.nonZeroModes.first?.range ?? rangeData.eco
        SharedBikeData.estimatedRange = bestRange
        let all = "eco=\(rangeData.eco) norm=\(rangeData.normal) pwr=\(rangeData.power) boost=\(rangeData.boost) smart=\(rangeData.smart)"
        logger.debug("Range: \(all, privacy: .public)")
        debugLog.log("GEV", "Range: \(all)")
    }

    private func handleReadFactoryData(_ plaintext: [UInt8]) {
        var factory = GiantProtocol.parseFactoryData(plaintext)
        // Frame number bytes are often zeros; use BLE device name instead (e.g., "GCHA12354")
        if let name = bikeManager?.connectedPeripheralName {
            factory?.frameNumber = name.trimmingCharacters(in: .whitespaces)
        }
        factoryData = factory
        saveFactoryData()
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
        UserDefaults.standard.set(batteryData.capacityPercent, forKey: "lastBatteryPercent")
        // Also update bikeInfo battery fields
        if var info = bikeInfo {
            GiantProtocol.parseBatteryIntoBikeInfo(plaintext, into: &info)
            bikeInfo = info
        }
        logger.debug(
            "Parsed battery data: capacity=\(batteryData.capacityPercent) life=\(batteryData.lifePercent)"
        )
        debugLog.log("GEV", "Battery: capacity=\(batteryData.capacityPercent)% life=\(batteryData.lifePercent)%")
        SharedBikeData.batteryPercent = batteryData.capacityPercent
        SharedBikeData.batteryHealth = batteryData.lifePercent
        SharedBikeData.lastConnected = Date()
        WidgetCenter.shared.reloadAllTimelines()
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
        // Calculate power from torque × cadence (P = τ × ω = τ × rpm × 2π/60)
        if parsed.cadence > 0 && parsed.torque > 0 {
            rideData.watts = parsed.torque * parsed.cadence * 2.0 * .pi / 60.0
        } else {
            rideData.watts = 0
        }
        if parsed.errorCode != 0 {
            rideData.errorCode = parsed.errorCode
        }
        logger.debug("SyncDrive: speed=\(parsed.speed) torque=\(parsed.torque) cadence=\(parsed.cadence) watts=\(self.rideData.watts) current=\(parsed.assistCurrent)A light=\(parsed.lightMode)")
        debugLog.log("GEV", "SyncDrive: speed=\(parsed.speed) torque=\(parsed.torque) cadence=\(parsed.cadence) watts=\(String(format: "%.0f", self.rideData.watts)) acur=\(parsed.assistCurrent)A light=\(parsed.lightMode)")
    }

    private func handleDiagnosticEnergyPak(_ plaintext: [UInt8]) {
        energyPakData = GiantProtocol.parseDiagnosticEnergyPak(plaintext)
        if let ep = energyPakData {
            logger.debug("EnergyPak: ecode=\(ep.errorCode) alarm=\(ep.alarm) uv=\(ep.underVoltageAlarm)")
            debugLog.log("GEV", "EnergyPak: ecode=\(ep.errorCode) alarm=\(ep.alarm) uv=\(ep.underVoltageAlarm)")
        }
    }

    private func handleBikeInfoResponse(_ plaintext: [UInt8], label: String) {
        let cmdID = plaintext[0]

        // First-response wins: skip if we've already processed this command
        if processedBikeDataCmds.contains(cmdID) {
            debugLog.log("GEV", "BikeInfo: \(label) duplicate response — skipping")
            return
        }
        processedBikeDataCmds.insert(cmdID)

        if bikeInfo == nil { bikeInfo = BikeInfo() }
        guard var info = bikeInfo else { return }
        switch cmdID {
        case GiantProtocol.Command.passiveRC1.rawValue:
            GiantProtocol.parseRCVersion(plaintext, into: &info)
        case GiantProtocol.Command.passiveRC2.rawValue:
            GiantProtocol.parseModeUsage(plaintext, into: &info)
        case GiantProtocol.Command.passiveRC3.rawValue,
             GiantProtocol.Command.passiveRC4.rawValue:
            GiantProtocol.parseRCErrorCode(plaintext, into: &info)
        case GiantProtocol.Command.passiveSD1.rawValue:
            GiantProtocol.parseMotorInfo(plaintext, into: &info)
        case GiantProtocol.Command.passiveSD2.rawValue:
            GiantProtocol.parseServiceData(plaintext, into: &info)
        case GiantProtocol.Command.passiveSD3.rawValue,
             GiantProtocol.Command.passiveSD4.rawValue:
            GiantProtocol.parseMotorErrorCode(plaintext, into: &info)
        case GiantProtocol.Command.passiveEP1.rawValue:
            GiantProtocol.parseEPVersion(plaintext, into: &info)
        case GiantProtocol.Command.passiveEP2.rawValue:
            GiantProtocol.parseEPChargeCycles(plaintext, into: &info)
        case GiantProtocol.Command.passiveEP3.rawValue:
            GiantProtocol.parseEPErrorCode(plaintext, into: &info)
        case GiantProtocol.Command.passiveEP4.rawValue:
            GiantProtocol.parseEPCapacity(plaintext, into: &info)
        case GiantProtocol.Command.activeSyncDrive.rawValue:
            GiantProtocol.parseODO(plaintext, into: &info)
        case GiantProtocol.Command.readBattery.rawValue:
            GiantProtocol.parseBatteryIntoBikeInfo(plaintext, into: &info)
        default:
            break
        }

        bikeInfo = info
        debugLog.log("GEV", "BikeInfo: \(label) parsed")
    }

    private func logTX(_ data: Data) {
        packetBuffer.append("TX \(hexString(data))")
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Automatic Snapshots & Error Logging

    private func recordBatterySnapshotIfNeeded() {
        guard let ctx = modelContext, let info = bikeInfo else { return }
        guard info.epLifePercent > 0 || info.epLastFullCapacityWh > 0 else { return }

        let lastDate = UserDefaults.standard.object(forKey: "lastBatterySnapshotDate") as? Date
        if let lastDate, Date.now.timeIntervalSince(lastDate) < 86400 { return }

        let snapshot = BatterySnapshot(
            capacityPercent: info.epCapacityPercent,
            healthPercent: info.epLifePercent,
            fullCapacityWh: info.epLastFullCapacityWh,
            chargeCycles: info.epChargeCycles,
            odometer: Double(info.odo)
        )
        ctx.insert(snapshot)
        UserDefaults.standard.set(Date.now, forKey: "lastBatterySnapshotDate")
        debugLog.log("GEV", "Battery snapshot recorded: health=\(info.epLifePercent)% cycles=\(info.epChargeCycles)")
    }

    private func recordErrorCodesIfNeeded() {
        guard let ctx = modelContext, let info = bikeInfo else { return }
        let odo = Double(info.odo)

        let lastKey = "lastErrorLogOdometer"
        let lastOdo = UserDefaults.standard.double(forKey: lastKey)
        guard odo != lastOdo else { return }

        func hasError(_ code: String) -> Bool {
            !code.isEmpty && !code.allSatisfy({ $0 == "0" })
        }

        var logged = false
        if hasError(info.motorErrorCode1) {
            ctx.insert(ErrorLogEntry(source: "motor", errorCode: info.motorErrorCode1, odometer: odo))
            logged = true
        }
        if hasError(info.motorErrorCode2) {
            ctx.insert(ErrorLogEntry(source: "motor", errorCode: info.motorErrorCode2, odometer: odo))
            logged = true
        }
        if hasError(info.rcErrorCode) {
            ctx.insert(ErrorLogEntry(source: "rideControl", errorCode: info.rcErrorCode, odometer: odo))
            logged = true
        }
        if hasError(info.rcNode2ErrorCode) {
            ctx.insert(ErrorLogEntry(source: "rideControl", errorCode: info.rcNode2ErrorCode, odometer: odo))
            logged = true
        }
        if hasError(info.epErrorCode) {
            ctx.insert(ErrorLogEntry(source: "energyPak", errorCode: info.epErrorCode, odometer: odo))
            logged = true
        }

        if logged {
            UserDefaults.standard.set(odo, forKey: lastKey)
        }
    }
}
