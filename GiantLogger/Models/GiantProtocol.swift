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

    // MARK: - AES Keys (from decompiled RideControl+ APK v1.32.1.0 GEVUtil.aesTable)

    static let aesKeys: [[UInt8]] = [
        [0x39, 0xFA, 0xD4, 0xC3, 0x93, 0x42, 0xAE, 0x41, 0x42, 0xA9, 0xA7, 0x77, 0x89, 0xA1, 0x13, 0xAF],
        [0x30, 0xEC, 0x00, 0xBD, 0x96, 0xF7, 0x21, 0x45, 0xD8, 0x46, 0xB0, 0x9A, 0x87, 0x29, 0xA6, 0x37],
        [0x6E, 0x0D, 0xE7, 0xE3, 0x04, 0xAE, 0x67, 0x2F, 0xE4, 0xA0, 0xBC, 0x3F, 0xF5, 0x04, 0x4D, 0x21],
        [0xB0, 0xB9, 0xC4, 0x7A, 0x62, 0x67, 0x67, 0xD0, 0x9D, 0x40, 0xE4, 0x82, 0xE2, 0xD7, 0x65, 0xEE],
        [0x5D, 0x2C, 0xB8, 0xE0, 0x04, 0xB0, 0x63, 0x57, 0xB0, 0x75, 0x92, 0xF4, 0xB2, 0x61, 0x84, 0xC1],
        [0x0D, 0x5E, 0x2F, 0x33, 0x96, 0x8A, 0x63, 0xEE, 0x5E, 0xF1, 0xFE, 0x06, 0x0E, 0x29, 0xCE, 0xF6],
        [0x58, 0xED, 0x11, 0xD1, 0xF8, 0x82, 0x82, 0x22, 0xE8, 0x86, 0x22, 0x63, 0x5B, 0xC8, 0x88, 0xC1],
        [0x13, 0xEF, 0x0A, 0x98, 0x51, 0xFF, 0xF3, 0x55, 0x21, 0xF2, 0x06, 0xC0, 0xAA, 0xD5, 0xD6, 0x06],
        [0x87, 0x18, 0xA0, 0xEF, 0xEA, 0x5A, 0xB7, 0x35, 0xEC, 0xBF, 0x1D, 0xA1, 0xA2, 0x39, 0x19, 0x8B],
        [0xA6, 0x4C, 0xD4, 0x19, 0x7A, 0xE3, 0x99, 0x4C, 0x19, 0x1E, 0xCC, 0x98, 0x26, 0xB9, 0x70, 0x8D],
        [0xFA, 0xAC, 0x80, 0x64, 0x4B, 0xF8, 0x46, 0xDD, 0xDF, 0x7C, 0xD0, 0xFA, 0x19, 0x85, 0xAC, 0x0B],
        [0x28, 0x98, 0xF9, 0x81, 0x44, 0xB6, 0xC3, 0x09, 0x64, 0x06, 0x7E, 0xBF, 0x27, 0x15, 0x6B, 0x2B],
        [0x17, 0xCB, 0x16, 0x36, 0x14, 0xAB, 0x6A, 0xA3, 0xE8, 0x4D, 0x26, 0x87, 0x4C, 0x0F, 0xD3, 0x47],
        [0x2A, 0xF5, 0x57, 0x69, 0xAE, 0x8A, 0xC8, 0x0D, 0x3B, 0x45, 0xAD, 0xAF, 0x35, 0xED, 0xAA, 0x06],
        [0xE7, 0xC2, 0x2E, 0x96, 0xB0, 0x74, 0x71, 0x9C, 0xCF, 0x19, 0x16, 0x1C, 0x69, 0x41, 0x79, 0xF0],
        [0x96, 0xB5, 0xF6, 0x8A, 0xAB, 0xDF, 0xE4, 0xB8, 0x7D, 0x6E, 0x65, 0x67, 0x51, 0xCD, 0xF3, 0x9E],
    ]

    // MARK: - Packet Construction

    /// Build a 20-byte GEV packet: [0xFB][0x21][16 AES-encrypted bytes][keyIndex][XOR CRC]
    /// Matches the Android RideControl+ APK packet format.
    static func buildPacket(command: Command, keyIndex: UInt8 = 0, data: [UInt8] = []) -> Data {
        var plaintext = [UInt8](repeating: 0, count: 16)
        plaintext[0] = command.rawValue
        plaintext[1] = keyIndex

        for (i, byte) in data.prefix(14).enumerated() {
            plaintext[i + 2] = byte
        }

        let encrypted = aesEncrypt(plaintext: plaintext, keyIndex: Int(keyIndex))

        // Packet: [0xFB, 0x21] + 16 encrypted + keyIndex + CRC(all 19 preceding bytes)
        var prelude: [UInt8] = [0xFB, 0x21]
        prelude.append(contentsOf: encrypted)
        prelude.append(keyIndex)
        let crc = xorCRC(prelude)

        var packet = Data(capacity: 20)
        packet.append(contentsOf: prelude)
        packet.append(crc)

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

    // MARK: - Packet Decoding

    /// Decode a 20-byte notification packet, returns 16-byte plaintext or nil.
    /// Format: [H0][H1][16 encrypted][keyIndex][CRC]
    /// The key index at byte 18 is sent in plaintext (no two-stage decryption needed).
    static func decodePacket(_ data: Data) -> [UInt8]? {
        guard data.count >= 20 else { return nil }

        let encrypted = Array(data[2...17])
        let keyIndex = Int(data[18])
        let receivedCRC = data[19]
        let computedCRC = xorCRC(Array(data[0...18]))
        guard receivedCRC == computedCRC else { return nil }

        guard keyIndex >= 0 && keyIndex < aesKeys.count else { return nil }
        return aesDecrypt(ciphertext: encrypted, keyIndex: keyIndex)
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
