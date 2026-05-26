import Foundation
@preconcurrency import CoreBluetooth
import Combine
import OSLog
import UIKit

// swiftlint:disable file_length

/// Manages BLE scanning, connection, and characteristic I/O for the Giant GEV service.
@MainActor
class BikeManager: NSObject, ObservableObject {

    enum ConnectionState: String {
        case disconnected
        case scanning
        case connecting
        case discoveringServices
        case connected
    }

    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String, rssi: Int)] = []
    @Published var connectedPeripheralName: String?

    /// Fires when a decoded notification is received
    let notificationReceived = PassthroughSubject<Data, Never>()

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private let serviceUUID = CBUUID(string: GiantProtocol.serviceUUID)
    private let writeCharUUID = CBUUID(string: GiantProtocol.writeCharUUID)
    private let notifyCharUUID = CBUUID(string: GiantProtocol.notifyCharUUID)
    private let logger = Logger(subsystem: "dk.hilli.GiantLogger", category: "BLE")
    private let debugLog = DebugLogger.shared

    // Auto-connect settings
    @Published var autoConnectIdentifier: UUID?
    private var connectTimeoutTask: Task<Void, Never>?
    private var foregroundReconnectTask: Task<Void, Never>?
    private var userInitiatedDisconnect = false

    override init() {
        super.init()
        // Restore auto-connect from UserDefaults
        if UserDefaults.standard.bool(forKey: "autoConnectEnabled"),
           let savedID = UserDefaults.standard.string(forKey: "savedDeviceID"),
           let uuid = UUID(uuidString: savedID) {
            autoConnectIdentifier = uuid
        }
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "dk.hilli.GiantLogger.central"
        ])
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan: bluetooth state is \(self.centralManager.state.rawValue)")
            debugLog.log("BLE", "Cannot scan: bluetooth state=\(centralManager.state.rawValue)")
            return
        }
        userInitiatedDisconnect = false
        logger.info("Starting scan for GEV service")
        debugLog.log("BLE", "Starting scan for GEV service")
        discoveredDevices.removeAll()
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Only timeout in foreground — background scans should persist
        if UIApplication.shared.applicationState == .active {
            Task {
                try? await Task.sleep(for: .seconds(15))
                if connectionState == .scanning {
                    stopScan()
                }
            }
        }
    }

    func stopScan() {
        logger.info("Stopping scan")
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    /// Attempt to reconnect to the saved device. Uses both a pending connect
    /// (instant if system has the peripheral cached) AND an active scan
    /// (forces the radio to discover the peripheral faster).
    func attemptAutoReconnect() {
        guard centralManager.state == .poweredOn,
              let savedID = autoConnectIdentifier else { return }

        userInitiatedDisconnect = false

        // If already connected or discovering services, nothing to do
        if connectionState == .connected || connectionState == .discoveringServices { return }

        // If stuck in .connecting or .scanning for too long, reset and retry
        if connectionState == .connecting || connectionState == .scanning {
            debugLog.log("BLE", "Auto-reconnect: resetting stale \(connectionState.rawValue) state")
            if let peripheral = connectedPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            centralManager.stopScan()
            cleanup()
        }

        // Check if already connected via another app or background restoration
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let peripheral = connected.first(where: { $0.identifier == savedID }) {
            debugLog.log("BLE", "Auto-reconnect: peripheral already connected, attaching")
            connect(to: peripheral)
            return
        }

        connectionState = .scanning

        // Issue a pending connect for the known peripheral. CoreBluetooth will
        // connect when it next sees the peripheral, but this can be slow without
        // active scanning since iOS waits passively.
        let known = centralManager.retrievePeripherals(withIdentifiers: [savedID])
        if let peripheral = known.first {
            debugLog.log("BLE", "Auto-reconnect: pending connect for cached peripheral")
            connectedPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }

        // Start active scan in parallel — forces the BLE radio to actively
        // search for advertisements, dramatically speeding up discovery.
        debugLog.log("BLE", "Auto-reconnect: starting active scan")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Timeout: stop scanning after 15s in foreground
        connectTimeoutTask?.cancel()
        if UIApplication.shared.applicationState == .active {
            connectTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                if connectionState == .scanning {
                    centralManager.stopScan()
                    if connectedPeripheral != nil {
                        // Direct connect is still pending, let it continue
                        connectionState = .connecting
                        debugLog.log("BLE", "Scan timed out; pending connect continues")
                    } else {
                        connectionState = .disconnected
                        debugLog.log("BLE", "Scan timed out; no peripheral found")
                    }
                }
            }
        }
    }

    /// Issue a pending connect for the saved peripheral so iOS can
    /// re-launch the app in the background when the bike appears.
    /// Safe to call even if already connected (will no-op).
    func ensurePendingConnect() {
        guard centralManager.state == .poweredOn,
              let savedID = autoConnectIdentifier else { return }
        if connectionState == .connected || connectionState == .discoveringServices { return }

        userInitiatedDisconnect = false

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [savedID])
        guard let peripheral = peripherals.first else {
            debugLog.log("BLE", "ensurePendingConnect: no cached peripheral for \(savedID)")
            return
        }
        debugLog.log("BLE", "ensurePendingConnect: issuing pending connect for background wake-up")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ])
    }

    func connect(to peripheral: CBPeripheral) {
        logger.info("Connecting to peripheral \(peripheral.identifier.uuidString, privacy: .public)")
        debugLog.log("BLE", "Connecting to \(peripheral.identifier.uuidString)")
        userInitiatedDisconnect = false
        connectTimeoutTask?.cancel()
        // Cancel any stale pending connect for a different peripheral object
        if let pending = connectedPeripheral, pending !== peripheral,
           pending.identifier == peripheral.identifier {
            centralManager.cancelPeripheralConnection(pending)
        }
        // Set .connecting BEFORE stopping scan to avoid a spurious .disconnected transition
        connectionState = .connecting
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(userInitiated: Bool = true) {
        logger.info("Disconnect requested")
        userInitiatedDisconnect = userInitiated
        if userInitiated {
            stopForegroundAutoReconnectLoop()
        }
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    func startForegroundAutoReconnectLoop() {
        guard foregroundReconnectTask == nil else { return }
        attemptAutoReconnect()

        foregroundReconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                guard UIApplication.shared.applicationState == .active else { continue }
                guard self.autoConnectIdentifier != nil else { break }
                if self.connectionState == .connected || self.connectionState == .discoveringServices {
                    break
                }
                self.debugLog.log("BLE", "Foreground auto-reconnect retry")
                self.attemptAutoReconnect()
            }
            self?.foregroundReconnectTask = nil
        }
    }

    func stopForegroundAutoReconnectLoop() {
        foregroundReconnectTask?.cancel()
        foregroundReconnectTask = nil
    }

    func write(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            logger.warning("Dropped TX packet: no connected peripheral or write characteristic")
            debugLog.log("BLE", "WARN: Dropped TX packet")
            return
        }
        logger.debug("TX \(data.count) bytes: \(data.hexString, privacy: .public)")
        debugLog.log("BLE", "TX \(data.count)B: \(data.hexString)")
        // Use .withoutResponse (matching Android's WRITE_TYPE_NO_RESPONSE)
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    /// Write without waiting for a BLE-level ACK (matches Android WRITE_TYPE_NO_RESPONSE).
    /// Used for trigger commands (light, assist, power) that are fire-and-forget.
    func writeWithoutResponse(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            logger.warning("Dropped TX packet: no connected peripheral or write characteristic")
            debugLog.log("BLE", "WARN: Dropped TX packet (no-response write)")
            return
        }
        logger.debug("TX (no-resp) \(data.count) bytes: \(data.hexString, privacy: .public)")
        debugLog.log("BLE", "TX (no-resp) \(data.count)B: \(data.hexString)")
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    private func cleanup() {
        connectTimeoutTask?.cancel()
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedPeripheralName = nil
        connectionState = .disconnected
    }
}

// MARK: - CBCentralManagerDelegate

extension BikeManager: @MainActor CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        debugLog.log("BLE", "State restoration triggered")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            connectedPeripheral = peripheral
            peripheral.delegate = self
            connectedPeripheralName = peripheral.name?.trimmingCharacters(in: .whitespaces)
            if peripheral.state == .connected {
                connectionState = .discoveringServices
                peripheral.discoverServices([serviceUUID])
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            logger.info("Central state updated: \(central.state.rawValue)")
            debugLog.log("BLE", "Central state: \(central.state.rawValue)")
            if central.state == .poweredOn {
                if UIApplication.shared.applicationState == .active {
                    startForegroundAutoReconnectLoop()
                } else {
                    attemptAutoReconnect()
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssiValue = RSSI.intValue
        Task { @MainActor in
            let name = peripheral.name ?? advertisedName ?? "Unknown"
            let identifier = peripheral.identifier.uuidString
            logger.debug(
                "Discovered \(name, privacy: .public) \(identifier, privacy: .public) RSSI=\(rssiValue)"
            )
            debugLog.log("BLE", "Discovered \(name) \(identifier) RSSI=\(rssiValue)")
            if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices.append((peripheral: peripheral, name: name, rssi: rssiValue))
            }
            // Auto-connect if matching saved identifier
            if let autoID = autoConnectIdentifier, peripheral.identifier == autoID {
                if let current = connectedPeripheral {
                    switch connectionState {
                    case .scanning, .connecting:
                        if current === peripheral {
                            debugLog.log("BLE", "Auto-reconnect: ignoring duplicate discovery for in-flight connection")
                            return
                        }
                    case .discoveringServices, .connected:
                        if current.identifier == peripheral.identifier {
                            debugLog.log("BLE", "Auto-reconnect: already attached to matching peripheral")
                            return
                        }
                    case .disconnected:
                        break
                    }
                }
                connect(to: peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            logger.info("Connected to peripheral \(peripheral.identifier.uuidString, privacy: .public)")
            debugLog.log("BLE", "Connected to \(peripheral.identifier.uuidString)")
            connectTimeoutTask?.cancel()
            centralManager.stopScan()
            connectionState = .discoveringServices
            connectedPeripheralName = peripheral.name?.trimmingCharacters(in: .whitespaces)
            let discoveredName = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier })?.name
            let savedName = (peripheral.name ?? discoveredName ?? "Unknown").trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(savedName, forKey: "savedDeviceName")
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "savedDeviceID")
            if autoConnectIdentifier != nil {
                autoConnectIdentifier = peripheral.identifier
                UserDefaults.standard.set(true, forKey: "autoConnectEnabled")
            }
            logger.debug("Saved device as \(savedName, privacy: .public)")
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if let error {
                logger.error("Disconnected with error: \(error.localizedDescription, privacy: .public)")
                debugLog.log("BLE", "ERROR: Disconnected: \(error.localizedDescription)")
            } else {
                logger.info("Disconnected from peripheral")
                debugLog.log("BLE", "Disconnected from peripheral")
            }
            let shouldReconnect = !userInitiatedDisconnect && autoConnectIdentifier != nil
            userInitiatedDisconnect = false
            cleanup()
            // Auto-reconnect unless the user explicitly disconnected.
            if shouldReconnect {
                let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "ble-reconnect") {
                    Task { @MainActor in
                        self.debugLog.log("BLE", "WARN: background task expired before reconnect retry")
                    }
                }
                debugLog.log("BLE", "Bike disconnected — will retry auto-reconnect")
                if UIApplication.shared.applicationState == .active {
                    try? await Task.sleep(for: .seconds(2))
                    startForegroundAutoReconnectLoop()
                } else {
                    attemptAutoReconnect()
                }
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            debugLog.log("BLE", "ERROR: Failed to connect: \(error?.localizedDescription ?? "unknown")")
            let shouldReconnect = !userInitiatedDisconnect && autoConnectIdentifier != nil
            userInitiatedDisconnect = false
            cleanup()
            if shouldReconnect {
                debugLog.log("BLE", "Connect failed — retrying auto-reconnect")
                if UIApplication.shared.applicationState == .active {
                    try? await Task.sleep(for: .seconds(2))
                    startForegroundAutoReconnectLoop()
                } else {
                    attemptAutoReconnect()
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BikeManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                logger.error("Discover services failed: \(error.localizedDescription, privacy: .public)")
                debugLog.log("BLE", "ERROR: Discover services failed: \(error.localizedDescription)")
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
                logger.error("GEV service not found on connected peripheral")
                debugLog.log("BLE", "ERROR: GEV service not found")
                disconnect(userInitiated: false)
                return
            }
            logger.debug("GEV service discovered, reading characteristics")
            peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                logger.error("Discover characteristics failed: \(error.localizedDescription, privacy: .public)")
            }
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == writeCharUUID {
                    writeCharacteristic = characteristic
                    let props = characteristic.properties
                    let propStr = [
                        props.contains(.write) ? "write" : nil,
                        props.contains(.writeWithoutResponse) ? "writeNoResp" : nil
                    ].compactMap { $0 }.joined(separator: ",")
                    logger.debug("Found write characteristic (props: \(propStr, privacy: .public))")
                    debugLog.log("BLE", "Found write characteristic (props: \(propStr))")
                } else if characteristic.uuid == notifyCharUUID {
                    notifyCharacteristic = characteristic
                    logger.debug("Found notify characteristic; enabling notifications")
                    debugLog.log("BLE", "Found notify characteristic; enabling notifications")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if writeCharacteristic != nil && notifyCharacteristic != nil {
                logger.info("Both characteristics found; waiting for notify confirmation")
                debugLog.log("BLE", "Both characteristics found; awaiting notify confirmation")
            } else {
                logger.error("Missing required characteristics for protocol")
                debugLog.log("BLE", "ERROR: Missing required characteristics")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                logger.error("Notify state update failed: \(error.localizedDescription, privacy: .public)")
                debugLog.log("BLE", "ERROR: Notify state failed: \(error.localizedDescription)")
                return
            }
            logger.info("Notify state for \(characteristic.uuid.uuidString, privacy: .public): \(characteristic.isNotifying)")
            debugLog.log("BLE", "Notify state \(characteristic.uuid.uuidString): isNotifying=\(characteristic.isNotifying)")

            // Transition to .connected only after the CCCD descriptor write is confirmed
            if characteristic.isNotifying && writeCharacteristic != nil && notifyCharacteristic != nil
                && connectionState != .connected {
                connectionState = .connected
                logger.info("Notification confirmed — BLE ready")
                debugLog.log("BLE", "Notification confirmed — BLE ready")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Task { @MainActor in
                logger.error("Notification value update failed: \(error.localizedDescription, privacy: .public)")
                debugLog.log("BLE", "ERROR: Value update failed: \(error.localizedDescription)")
            }
            return
        }
        guard let data = characteristic.value, characteristic.uuid == CBUUID(string: GiantProtocol.notifyCharUUID) else { return }
        Task { @MainActor in
            logger.debug("RX raw notify \(data.count) bytes: \(data.hexString, privacy: .public)")
            debugLog.log("BLE", "RX \(data.count)B: \(data.hexString)")
            notificationReceived.send(data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task { @MainActor in
            if let error {
                logger.error("BLE write failed: \(error.localizedDescription, privacy: .public)")
                debugLog.log("BLE", "ERROR: Write failed: \(error.localizedDescription)")
            }
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
