import Foundation
import CommonCrypto

// MARK: - Giant GEV BLE Protocol
// Ported from giant-esp32/src/giant_protocol.cpp
// Protocol details reverse-engineered from RideControl+ APK v1.32.1.0

enum GiantProtocol {

    // MARK: - BLE UUIDs

    static let serviceUUID = "4D500001-4745-5630-3031-E50E24DCCA9E"
    static let writeCharUUID = "4D500002-4745-5630-3031-E50E24DCCA9E"
    static let notifyCharUUID = "4D500003-4745-5630-3031-E50E24DCCA9E"

    // MARK: - Command IDs

    enum Command: UInt8 {
        case connectGEV          = 0x02
        case readFactoryData     = 0x03
        case readBattery         = 0x13
        case diagnosticSyncDrive = 0x16
        case diagnosticEnergyPak = 0x17
        case readRidingData      = 0x1B
        case triggerAction       = 0x1C
        case readRemainingRange  = 0x1D
        case disconnectGEV       = 0x21
        case readTuningData      = 0x2C
    }

    // MARK: - Trigger Actions

    enum TriggerAction: UInt8 {
        case power     = 0x00
        case assistDown = 0x01
        case assistUp  = 0x02
        case light     = 0x08
    }

    // MARK: - AES Keys (from decompiled RideControl+ APK)

    static let aesKeys: [[UInt8]] = [
        [0xD0, 0xB0, 0xE8, 0x52, 0x7C, 0x25, 0x78, 0x0C, 0x5F, 0x09, 0x1E, 0x79, 0xEF, 0x62, 0x15, 0x2C],
        [0x6D, 0x65, 0x12, 0xE2, 0x34, 0x76, 0x56, 0x10, 0x20, 0xB7, 0xF6, 0x6A, 0x04, 0xBA, 0xDE, 0xD4],
        [0x43, 0x55, 0x14, 0x6D, 0xA5, 0x7C, 0x96, 0x5E, 0x16, 0x30, 0x13, 0xF9, 0x3A, 0x7E, 0xD3, 0x0F],
        [0xE4, 0x14, 0x9F, 0x5A, 0x28, 0x24, 0x93, 0xC0, 0x55, 0x33, 0xAE, 0x57, 0xF0, 0x39, 0x2D, 0x8C],
        [0x80, 0x56, 0x66, 0x6E, 0x88, 0x5D, 0xB9, 0x4E, 0xDD, 0xEF, 0xA5, 0xE9, 0xE8, 0x06, 0x0E, 0x48],
        [0x5D, 0xAD, 0x4E, 0x36, 0x07, 0x0E, 0x50, 0x11, 0xB8, 0x5A, 0x6B, 0xE3, 0x4A, 0x0C, 0x73, 0x76],
        [0x7F, 0x18, 0x1E, 0x3F, 0x4A, 0x84, 0xE5, 0x38, 0x43, 0x89, 0xE1, 0xB5, 0xD5, 0x3C, 0xF3, 0xD8],
        [0xD5, 0x57, 0xA6, 0xFE, 0x43, 0x6F, 0x0F, 0x73, 0x71, 0x02, 0xC8, 0x99, 0xAA, 0xFD, 0xC5, 0xE3],
        [0x20, 0x4B, 0x36, 0x52, 0x87, 0xBC, 0xAC, 0x69, 0x7C, 0x5B, 0x50, 0x63, 0x24, 0xD2, 0x05, 0xE7],
        [0x70, 0xC4, 0x56, 0xFE, 0x43, 0x6F, 0x35, 0x20, 0x71, 0x02, 0xC8, 0x99, 0xAA, 0xFD, 0xC5, 0xE3],
        [0xA0, 0x55, 0x36, 0x52, 0x87, 0xBC, 0xAC, 0x49, 0x7C, 0x5B, 0x50, 0x63, 0x24, 0xD2, 0x05, 0xE7],
        [0x72, 0x43, 0x12, 0xFE, 0x43, 0x6F, 0x35, 0x73, 0x71, 0x02, 0xC8, 0x99, 0xAA, 0xFD, 0xC5, 0xE3],
        [0x21, 0x4B, 0x36, 0x52, 0x87, 0xBC, 0xAC, 0x69, 0x7C, 0x5B, 0x52, 0x63, 0x24, 0xD2, 0x05, 0xE7],
        [0xD0, 0x55, 0xA5, 0xFE, 0x43, 0x6F, 0x35, 0x73, 0x71, 0x02, 0xC8, 0x99, 0xAA, 0xFD, 0xC5, 0xE3],
        [0x22, 0x4B, 0x36, 0x52, 0x87, 0xBC, 0xAC, 0x69, 0x7C, 0x5B, 0x50, 0x63, 0x24, 0xD2, 0x05, 0xE7],
        [0xA5, 0x57, 0xA6, 0xFE, 0x43, 0x6F, 0x35, 0x73, 0x71, 0x02, 0xC8, 0x99, 0xAA, 0xFD, 0xC5, 0xE3],
    ]

    // MARK: - Packet Construction

    /// Build an 18-byte GEV packet: [0x21][16 AES-encrypted bytes][XOR CRC]
    static func buildPacket(command: Command, keyIndex: UInt8 = 0, data: [UInt8] = []) -> Data {
        var plaintext = [UInt8](repeating: 0, count: 16)
        plaintext[0] = command.rawValue
        plaintext[1] = keyIndex

        for (i, byte) in data.prefix(14).enumerated() {
            plaintext[i + 2] = byte
        }

        let encrypted = aesEncrypt(plaintext: plaintext, keyIndex: Int(keyIndex))

        var packet = Data(capacity: 18)
        packet.append(0x21) // header
        packet.append(contentsOf: encrypted)
        packet.append(xorCRC(encrypted))

        return packet
    }

    // MARK: - Predefined Commands

    static func connectCommand() -> Data {
        buildPacket(command: .connectGEV)
    }

    static func disconnectCommand() -> Data {
        buildPacket(command: .disconnectGEV)
    }

    static func readRidingDataCommand() -> Data {
        buildPacket(command: .readRidingData)
    }

    static func readFactoryDataCommand() -> Data {
        buildPacket(command: .readFactoryData)
    }

    static func readBatteryCommand() -> Data {
        buildPacket(command: .readBattery)
    }

    static func readRemainingRangeCommand() -> Data {
        buildPacket(command: .readRemainingRange)
    }

    static func diagnosticEnergyPakCommand() -> Data {
        buildPacket(command: .diagnosticEnergyPak)
    }

    static func diagnosticSyncDriveCommand() -> Data {
        buildPacket(command: .diagnosticSyncDrive)
    }

    static func triggerLightCommand() -> Data {
        buildPacket(command: .triggerAction, keyIndex: 3, data: [TriggerAction.light.rawValue])
    }

    static func triggerAssistUpCommand() -> Data {
        buildPacket(command: .triggerAction, keyIndex: 3, data: [TriggerAction.assistUp.rawValue])
    }

    static func triggerAssistDownCommand() -> Data {
        buildPacket(command: .triggerAction, keyIndex: 3, data: [TriggerAction.assistDown.rawValue])
    }

    static func triggerPowerCommand() -> Data {
        buildPacket(command: .triggerAction, keyIndex: 3, data: [TriggerAction.power.rawValue, 0x08])
    }

    // MARK: - Packet Decoding (two-stage decryption)

    /// Decode an 18-byte notification packet, returns 16-byte plaintext or nil
    static func decodePacket(_ data: Data) -> [UInt8]? {
        guard data.count == 18, data[0] == 0x21 else { return nil }

        let encrypted = Array(data[1...16])
        let receivedCRC = data[17]
        let computedCRC = xorCRC(encrypted)
        guard receivedCRC == computedCRC else { return nil }

        // Stage 1: decrypt with key 0 to read key index
        let stage1 = aesDecrypt(ciphertext: encrypted, keyIndex: 0)
        let keyIndex = Int(stage1[1])

        // Stage 2: if key index != 0, re-decrypt with correct key
        if keyIndex != 0 && keyIndex < aesKeys.count {
            return aesDecrypt(ciphertext: encrypted, keyIndex: keyIndex)
        }
        return stage1
    }

    // MARK: - Response Parsing

    static func parseRidingData(_ plain: [UInt8]) -> RideData? {
        guard plain[0] == Command.readRidingData.rawValue else { return nil }
        return RideData(
            speed: Double(bigEndianUInt16(plain, offset: 2)) / 10.0,
            cadence: Double(bigEndianUInt16(plain, offset: 4)) / 10.0,
            torque: Double(bigEndianUInt16(plain, offset: 6)) / 100.0,
            watts: Double(bigEndianUInt16(plain, offset: 8)) / 10.0,
            batteryPercent: Int(plain[10]),
            distance: Double(bigEndianUInt16(plain, offset: 11)) / 10.0,
            rideTime: Int(bigEndianUInt16(plain, offset: 13)),
            range: 0,
            errorCode: Int(plain[15])
        )
    }

    static func parseFactoryData(_ plain: [UInt8]) -> FactoryData? {
        guard plain[0] == Command.readFactoryData.rawValue else { return nil }
        let frameBytes = Array(plain[2...12])
        let frameNumber = String(bytes: frameBytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        return FactoryData(
            frameNumber: frameNumber,
            rcType: Int(plain[13]),
            rcHardwareVersion: bigEndianUInt16(plain, offset: 14)
        )
    }

    static func parseRemainingRange(_ plain: [UInt8]) -> Int? {
        guard plain[0] == Command.readRemainingRange.rawValue else { return nil }
        return Int(bigEndianUInt16(plain, offset: 2))
    }

    static func parseBatteryData(_ plain: [UInt8]) -> BatteryData? {
        guard plain[0] == Command.readBattery.rawValue else { return nil }
        return BatteryData(
            capacityPercent: Int(plain[2]),
            lifePercent: Int(plain[3]),
            lastFullCapacityWh: Double(bigEndianUInt16(plain, offset: 4)) / 10.0
        )
    }

    static func parseDiagnosticSyncDrive(_ plain: [UInt8]) -> SyncDriveData? {
        guard plain[0] == Command.diagnosticSyncDrive.rawValue else { return nil }
        let fwVersion = "\(plain[3]).\(plain[4]).\(plain[5])"
        let odometer = bigEndianUInt32(plain, offset: 6)
        return SyncDriveData(
            duType: Int(plain[2]),
            firmwareVersion: fwVersion,
            odometer: Int(odometer)
        )
    }

    static func parseDiagnosticEnergyPak(_ plain: [UInt8]) -> EnergyPakData? {
        guard plain[0] == Command.diagnosticEnergyPak.rawValue else { return nil }
        let fwVersion = "\(plain[4]).\(plain[5]).\(plain[6])"
        return EnergyPakData(
            capacityPercent: Int(plain[2]),
            lifePercent: Int(plain[3]),
            firmwareVersion: fwVersion
        )
    }

    // MARK: - AES Helpers

    private static func aesEncrypt(plaintext: [UInt8], keyIndex: Int) -> [UInt8] {
        let key = aesKeys[keyIndex % aesKeys.count]
        var encrypted = [UInt8](repeating: 0, count: 16)
        var outLength: Int = 0

        _ = key.withUnsafeBufferPointer { keyPtr in
            plaintext.withUnsafeBufferPointer { dataPtr in
                encrypted.withUnsafeMutableBufferPointer { outPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, kCCKeySizeAES128,
                        nil,
                        dataPtr.baseAddress, 16,
                        outPtr.baseAddress, 16,
                        &outLength
                    )
                }
            }
        }
        return encrypted
    }

    private static func aesDecrypt(ciphertext: [UInt8], keyIndex: Int) -> [UInt8] {
        let key = aesKeys[keyIndex % aesKeys.count]
        var decrypted = [UInt8](repeating: 0, count: 16)
        var outLength: Int = 0

        _ = key.withUnsafeBufferPointer { keyPtr in
            ciphertext.withUnsafeBufferPointer { dataPtr in
                decrypted.withUnsafeMutableBufferPointer { outPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, kCCKeySizeAES128,
                        nil,
                        dataPtr.baseAddress, 16,
                        outPtr.baseAddress, 16,
                        &outLength
                    )
                }
            }
        }
        return decrypted
    }

    private static func xorCRC(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0, ^)
    }

    private static func bigEndianUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func bigEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 |
        UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
}

// MARK: - Protocol Data Types

struct RideData: Equatable {
    var speed: Double = 0        // km/h
    var cadence: Double = 0      // RPM
    var torque: Double = 0       // Nm
    var watts: Double = 0        // W
    var batteryPercent: Int = 0  // 0-100
    var distance: Double = 0     // km
    var rideTime: Int = 0        // seconds
    var range: Int = 0           // km
    var errorCode: Int = 0
}

struct FactoryData: Equatable {
    var frameNumber: String = ""
    var rcType: Int = 0
    var rcHardwareVersion: UInt16 = 0
}

struct BatteryData: Equatable {
    var capacityPercent: Int = 0
    var lifePercent: Int = 0
    var lastFullCapacityWh: Double = 0
}

struct SyncDriveData: Equatable {
    var duType: Int = 0
    var firmwareVersion: String = ""
    var odometer: Int = 0
}

struct EnergyPakData: Equatable {
    var capacityPercent: Int = 0
    var lifePercent: Int = 0
    var firmwareVersion: String = ""
}
