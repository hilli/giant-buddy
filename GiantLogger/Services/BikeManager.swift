import Foundation
import CoreBluetooth
import Combine

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

    // Auto-connect settings
    @Published var autoConnectIdentifier: UUID?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Stop scanning after 15 seconds
        Task {
            try? await Task.sleep(for: .seconds(15))
            if connectionState == .scanning {
                stopScan()
            }
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        connectionState = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    func write(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func cleanup() {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedPeripheralName = nil
        connectionState = .disconnected
    }
}

// MARK: - CBCentralManagerDelegate

extension BikeManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                if autoConnectIdentifier != nil {
                    startScan()
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
            if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices.append((peripheral: peripheral, name: name, rssi: RSSI.intValue))
            }
            // Auto-connect if matching saved identifier
            if let autoID = autoConnectIdentifier, peripheral.identifier == autoID {
                connect(to: peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = .discoveringServices
            connectedPeripheralName = peripheral.name
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            cleanup()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BikeManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
                disconnect()
                return
            }
            peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == writeCharUUID {
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == notifyCharUUID {
                    notifyCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if writeCharacteristic != nil && notifyCharacteristic != nil {
                connectionState = .connected
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, characteristic.uuid == CBUUID(string: GiantProtocol.notifyCharUUID) else { return }
        Task { @MainActor in
            notificationReceived.send(data)
        }
    }
}
