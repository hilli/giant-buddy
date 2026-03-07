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
        case passiveRC1          = 0x05  // PASSIVE_DATA_RIDE_CONTROL_1 — RC FW/HW version
        case passiveRC2          = 0x06  // PASSIVE_DATA_RIDE_CONTROL_2 — mode usage %
        case passiveRC3          = 0x07  // PASSIVE_DATA_RIDE_CONTROL_3 — RC error code
        case passiveRC4          = 0x08  // PASSIVE_DATA_RIDE_CONTROL_4 — RC node2 error code
        case passiveSD1          = 0x09  // PASSIVE_DATA_SYNC_DRIVE_1 — motor FW/HW/type/PSN
        case passiveSD2          = 0x0A  // PASSIVE_DATA_SYNC_DRIVE_2 — service + avg amps
        case passiveSD3          = 0x0B  // PASSIVE_DATA_SYNC_DRIVE_3 — motor error code 1
        case passiveSD4          = 0x0C  // PASSIVE_DATA_SYNC_DRIVE_4 — motor error code 2
        case passiveEP1          = 0x0D  // PASSIVE_DATA_ENERGY_PAK_1 — EP version
        case passiveEP2          = 0x0E  // PASSIVE_DATA_ENERGY_PAK_2 — EP charge cycles
        case passiveEP3          = 0x0F  // PASSIVE_DATA_ENERGY_PAK_3 — EP error code
        case passiveEP4          = 0x10  // PASSIVE_DATA_ENERGY_PAK_4 — EP capacity + dnc
        case bikeDataRideControl = 0x11  // ACTIVE_DATA_RIDE_CONTROL_1 — range per assist mode
        case activeSyncDrive     = 0x12  // ACTIVE_DATA_SYNC_DRIVE_1 — ODO + total hours
        case readBattery         = 0x13  // ACTIVE_DATA_ENERGY_PAK_1 — battery %/life/capacity
        case diagnosticSyncDrive = 0x16
        case diagnosticEnergyPak = 0x17
        case readRidingData      = 0x1B
        case triggerAction       = 0x1C
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

    static func readBikeDataRideControlCommand() -> Data {
        buildPacket(command: .bikeDataRideControl)
    }

    /// Build command for any readSingleBikeData request (commands 0x05-0x13)
    static func readSingleBikeDataCommand(_ command: Command) -> Data {
        buildPacket(command: command)
    }

    /// All passive/active bike data commands to fetch full bike info
    static let allBikeDataCommands: [Command] = [
        .passiveRC1, .passiveRC2, .passiveRC3, .passiveRC4,
        .passiveSD1, .passiveSD2, .passiveSD3, .passiveSD4,
        .passiveEP1, .passiveEP2, .passiveEP3, .passiveEP4,
        .bikeDataRideControl, .activeSyncDrive, .readBattery,
    ]

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
            speed: Double(littleEndianUInt16(plain, offset: 2)) / 10.0,
            cadence: Double(littleEndianUInt16(plain, offset: 6)) / 10.0,
            torque: Double(littleEndianUInt16(plain, offset: 4)) / 10.0,
            watts: Double(littleEndianUInt16(plain, offset: 8)) / 10.0,
            batteryPercent: Int(plain[10]),
            distance: Double(littleEndianUInt16(plain, offset: 11)) / 10.0,
            rideTime: Int(littleEndianUInt16(plain, offset: 13)),
            errorCode: Int(plain[15])
        )
    }

    static func parseFactoryData(_ plain: [UInt8]) -> FactoryData? {
        guard plain[0] == Command.readFactoryData.rawValue else { return nil }
        // Android: d.i(2, 16, decrypted) → bArrS[0..13]
        // bArrS[0] = speedLimitation, bArrS[1:2] = circumference (LE short),
        // bArrS[3:7] = frameNumber (bit-encoded), bArrS[8] = evCategory,
        // bArrS[10:13] = rcHwVersion (hex string)
        let speedLim = Int(plain[2])
        let circumference = Int(littleEndianUInt16(plain, offset: 3))
        let rcHwBytes = Array(plain[12...15])
        let rcHwVersion = rcHwBytes.map { String(format: "%02X", $0) }.joined()
        return FactoryData(
            speedLimitation: speedLim,
            circumference: circumference,
            frameNumber: "",  // populated from BLE peripheral name
            evCategory: Int(plain[10]),
            rcHardwareVersion: rcHwVersion
        )
    }

    /// Parse ACTIVE_DATA_RIDE_CONTROL_1 (0x11) response into per-mode range estimates.
    /// Byte mapping from Android APK `readRemainingRange()`:
    /// plaintext[2..13] → eco, normal, power, boostPlus, boost, powerPlus,
    ///                     climbPlus, climb, normalPlus, tourPlus, tour, smart
    static func parseRemainingRange(_ plain: [UInt8]) -> RemainingRangeData? {
        guard plain[0] == Command.bikeDataRideControl.rawValue else { return nil }
        return RemainingRangeData(
            eco: Int(plain[2]),
            normal: Int(plain[3]),
            power: Int(plain[4]),
            boostPlus: Int(plain[5]),
            boost: Int(plain[6]),
            powerPlus: Int(plain[7]),
            climbPlus: Int(plain[8]),
            climb: Int(plain[9]),
            normalPlus: Int(plain[10]),
            tourPlus: Int(plain[11]),
            tour: Int(plain[12]),
            smart: Int(plain[13])
        )
    }

    static func parseBatteryData(_ plain: [UInt8]) -> BatteryData? {
        guard plain[0] == Command.readBattery.rawValue else { return nil }
        return BatteryData(
            capacityPercent: Int(plain[2]),
            lifePercent: Int(plain[3]),
            lastFullCapacityWh: Double(littleEndianUInt16(plain, offset: 4)) / 10.0
        )
    }

    static func parseDiagnosticSyncDrive(_ plain: [UInt8]) -> SyncDriveData? {
        guard plain[0] == Command.diagnosticSyncDrive.rawValue else { return nil }
        // Android: bArrI = d.i(2, 16, decrypted) → indices map to plain[2..15]
        // bArrI[0]=ecode, [1:2]=speed/10, [3:4]=torque/10, [5:6]=cadence/10,
        // [7:8]=acur/10, [9]=rsoce, [10]=light (bits 4-5: mask 0x30 >> 4)
        return SyncDriveData(
            errorCode: Int(plain[2]),
            speed: Double(littleEndianUInt16(plain, offset: 3)) / 10.0,
            torque: Double(littleEndianUInt16(plain, offset: 5)) / 10.0,
            cadence: Double(littleEndianUInt16(plain, offset: 7)) / 10.0,
            assistCurrent: Double(littleEndianUInt16(plain, offset: 9)) / 10.0,
            rsoc: Int(plain[11]),
            lightMode: Int((plain[12] & 0x30) >> 4)
        )
    }

    static func parseDiagnosticEnergyPak(_ plain: [UInt8]) -> EnergyPakData? {
        guard plain[0] == Command.diagnosticEnergyPak.rawValue else { return nil }
        // Android: bArrI[0]=ecode, bArrI[1]=alm, alaUv=(bArrI[1] & 50) >= 1
        return EnergyPakData(
            errorCode: Int(plain[2]),
            alarm: Int(plain[3]),
            underVoltageAlarm: (plain[3] & 50) >= 1
        )
    }

    // MARK: - BikeInfo Parsers (readSingleBikeData responses)

    /// Parse RC FW/HW version (cmd 0x05, PASSIVE_DATA_RIDE_CONTROL_1)
    static func parseRCVersion(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveRC1.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 8 else { return }
        let fwYear = Int(b[2] & 0x1F) + 2000
        let fwMonth = Int(b[1] & 0x1F)
        let fwDay = Int(b[0] & 0x1F)
        let fwBuild = Int(b[3] & 0x1F)
        info.rcFwVersion = String(format: "%04d%02d%02d%03d", fwYear, fwMonth, fwDay, fwBuild)
        let hwYear = Int(b[5] & 0x1F) + 2000
        let hwMonth = Int(b[4] & 0x0F)
        let hwSerial = Int(littleEndianUInt16([b[6], b[7]], offset: 0))
        info.rcHwVersion = String(format: "%04d%02d%05d", hwYear, hwMonth, hwSerial)
    }

    /// Parse mode usage percentages (cmd 0x06, PASSIVE_DATA_RIDE_CONTROL_2)
    static func parseModeUsage(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveRC2.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 13 else { return }
        info.modeUsage = ModeUsageData(
            smart: Int(b[0]), boostPlus: Int(b[1]), boost: Int(b[2]),
            powerPlus: Int(b[3]), power: Int(b[4]), climbPlus: Int(b[5]),
            climb: Int(b[6]), normalPlus: Int(b[7]), normal: Int(b[8]),
            tourPlus: Int(b[9]), tour: Int(b[10]), eco: Int(b[11]),
            off: Int(b[12])
        )
    }

    /// Parse RC error codes (cmd 0x07, 0x08)
    static func parseRCErrorCode(_ plain: [UInt8], into info: inout BikeInfo) {
        let hex = plain[2...].map { String(format: "%02X", $0) }.joined()
        if plain[0] == Command.passiveRC3.rawValue {
            info.rcErrorCode = hex
        } else if plain[0] == Command.passiveRC4.rawValue {
            info.rcNode2ErrorCode = hex
        }
    }

    /// Parse motor FW/HW version, type, PSN (cmd 0x09, PASSIVE_DATA_SYNC_DRIVE_1)
    static func parseMotorInfo(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveSD1.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 13 else { return }
        // Model name: first 4 ASCII chars (e.g. "2YA0")
        info.motorModel = (0...3).map { String(UnicodeScalar(b[$0])) }.joined()
        // FW version: year(20XX)+month+day+revision  (b[4]=year-2000, b[5]=month, b[6]=day hex, b[7]=revision ASCII)
        let year = 2000 + Int(b[4])
        let month = Int(b[5])
        let day = Int(b[6])
        let rev = String(UnicodeScalar(b[7]))
        info.motorFwVersion = String(format: "%04d%02d%02d%@", year, month, day, rev)
        // HW: 5 ASCII chars
        info.motorHwVersion = (8...12).map { String(UnicodeScalar(b[$0])) }.joined()
    }

    /// Parse service + avg amps (cmd 0x0A, PASSIVE_DATA_SYNC_DRIVE_2)
    static func parseServiceData(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveSD2.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 14 else { return }
        info.serviceToolConnections = Int(littleEndianUInt16([b[0], b[1]], offset: 0))
        info.lastServiceHoursAgo = Int(littleEndianUInt16([b[2], b[3]], offset: 0))
        info.lastServiceKmAgo = Int(littleEndianUInt16([b[4], b[5]], offset: 0))
        info.avgAmpsBoost = Double(Int16(bitPattern: littleEndianUInt16([b[6], b[7]], offset: 0))) / 100.0
        info.avgAmpsPower = Double(Int16(bitPattern: littleEndianUInt16([b[8], b[9]], offset: 0))) / 100.0
        info.avgAmpsClimb = Double(Int16(bitPattern: littleEndianUInt16([b[10], b[11]], offset: 0))) / 100.0
        info.avgAmpsNormal = Double(Int16(bitPattern: littleEndianUInt16([b[12], b[13]], offset: 0))) / 100.0
        // Note: tourAvgA and ecoAvgA are at b[14:15] and b[16:17] but we only have 14 bytes of payload
        // They come through if the response has enough data
        if b.count > 15 {
            info.avgAmpsTour = Double(Int16(bitPattern: littleEndianUInt16([b[14], b[15]], offset: 0))) / 100.0
        }
        if b.count > 17 {
            info.avgAmpsEco = Double(Int16(bitPattern: littleEndianUInt16([b[16], b[17]], offset: 0))) / 100.0
        }
    }

    /// Parse motor error codes (cmd 0x0B, 0x0C)
    static func parseMotorErrorCode(_ plain: [UInt8], into info: inout BikeInfo) {
        let hex = plain[2...].map { String(format: "%02X", $0) }.joined()
        if plain[0] == Command.passiveSD3.rawValue {
            info.motorErrorCode1 = hex
        } else if plain[0] == Command.passiveSD4.rawValue {
            info.motorErrorCode2 = hex
        }
    }

    /// Parse EnergyPak version (cmd 0x0D, PASSIVE_DATA_ENERGY_PAK_1)
    static func parseEPVersion(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveEP1.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 7 else { return }
        let typeHex = String(format: "%02x", b[0])
        let mfg = b[1] == 0 ? "PF" : "GA"
        let year = Int(b[2]) + 2000
        let month = Int(b[3])
        let day = Int(b[4])
        let serial = Int(littleEndianUInt16([b[5], b[6]], offset: 0))
        info.epVersion = typeHex + mfg + String(format: "%04d%02d%02d%05d", year, month, day, serial)
    }

    /// Parse EnergyPak charge cycles (cmd 0x0E, PASSIVE_DATA_ENERGY_PAK_2)
    static func parseEPChargeCycles(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveEP2.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 5 else { return }
        info.epChargeCycles = Int(littleEndianUInt16([b[0], b[1]], offset: 0))
        info.epChargeTimes = Int(littleEndianUInt16([b[2], b[3]], offset: 0))
        info.epDischargePercent = Int(b[4])
    }

    /// Parse EnergyPak error code (cmd 0x0F, PASSIVE_DATA_ENERGY_PAK_3)
    static func parseEPErrorCode(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveEP3.rawValue else { return }
        info.epErrorCode = plain[2...].map { String(format: "%02X", $0) }.joined()
    }

    /// Parse EnergyPak capacity details (cmd 0x10, PASSIVE_DATA_ENERGY_PAK_4)
    static func parseEPCapacity(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.passiveEP4.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 6 else { return }
        info.epMaxNotChargedDays = Int(littleEndianUInt16([b[0], b[1]], offset: 0))
        info.epNotChargedCycles = Int(littleEndianUInt16([b[2], b[3]], offset: 0))
        info.epCapacityWh = Double(Int16(bitPattern: littleEndianUInt16([b[4], b[5]], offset: 0))) / 10.0
    }

    /// Parse ODO + total usage hours (cmd 0x12, ACTIVE_DATA_SYNC_DRIVE_1)
    static func parseODO(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.activeSyncDrive.rawValue else { return }
        let b = Array(plain[2...])
        guard b.count >= 4 else { return }
        info.odo = Int(littleEndianUInt16([b[0], b[1]], offset: 0))
        info.totalUsageHours = Int(littleEndianUInt16([b[2], b[3]], offset: 0))
    }

    /// Parse battery capacity/life/fullCapacity (cmd 0x13) into BikeInfo
    static func parseBatteryIntoBikeInfo(_ plain: [UInt8], into info: inout BikeInfo) {
        guard plain[0] == Command.readBattery.rawValue else { return }
        info.epCapacityPercent = Int(plain[2])
        info.epLifePercent = Int(plain[3])
        info.epLastFullCapacityWh = Double(littleEndianUInt16(plain, offset: 4)) / 10.0
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

    private static func littleEndianUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
        UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
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
    var rangeData: RemainingRangeData? // per-mode range from 0x11
    var errorCode: Int = 0
    var assistCurrent: Double = 0 // Amps from motor
    var lightMode: Int = 0        // 0=OFF, 1=ON, 2=LOW, 3=HIGH

    /// Best available range estimate: eco (max range) when all modes are available
    var range: Int {
        rangeData?.eco ?? 0
    }
}

struct FactoryData: Equatable {
    var speedLimitation: Int = 0      // raw value (÷10 for km/h)
    var circumference: Int = 0        // wheel circumference in mm
    var frameNumber: String = ""      // from BLE device name
    var evCategory: Int = 0
    var rcHardwareVersion: String = ""
}

struct BatteryData: Equatable {
    var capacityPercent: Int = 0
    var lifePercent: Int = 0
    var lastFullCapacityWh: Double = 0
}

struct SyncDriveData: Equatable {
    var errorCode: Int = 0        // motor error code
    var speed: Double = 0         // km/h
    var torque: Double = 0        // Nm
    var cadence: Double = 0       // RPM
    var assistCurrent: Double = 0 // Amps
    var rsoc: Int = 0             // remaining state of charge
    var lightMode: Int = 0        // 0=OFF, 1=ON, 2=LOW, 3=HIGH
}

struct EnergyPakData: Equatable {
    var errorCode: Int = 0
    var alarm: Int = 0
    var underVoltageAlarm: Bool = false
}

/// Range estimates (km) per assist mode from ACTIVE_DATA_RIDE_CONTROL_1 (0x11).
struct RemainingRangeData: Equatable {
    var eco: Int = 0
    var normal: Int = 0
    var power: Int = 0
    var boostPlus: Int = 0
    var boost: Int = 0
    var powerPlus: Int = 0
    var climbPlus: Int = 0
    var climb: Int = 0
    var normalPlus: Int = 0
    var tourPlus: Int = 0
    var tour: Int = 0
    var smart: Int = 0

    /// All modes as label-value pairs (only non-zero)
    var nonZeroModes: [(label: String, range: Int)] {
        let all: [(String, Int)] = [
            ("Eco", eco), ("Normal", normal), ("Normal+", normalPlus),
            ("Tour", tour), ("Tour+", tourPlus),
            ("Power", power), ("Power+", powerPlus),
            ("Boost", boost), ("Boost+", boostPlus),
            ("Climb", climb), ("Climb+", climbPlus),
            ("Smart", smart),
        ]
        return all.filter { $0.1 > 0 }
    }
}

// MARK: - BikeInfo (cached bike data from readSingleBikeData commands 0x05-0x13)

struct BikeInfo: Codable, Equatable {
    // Overview (0x12)
    var odo: Int = 0
    var totalUsageHours: Int = 0

    // Ride Control (0x05)
    var rcFwVersion: String = ""
    var rcHwVersion: String = ""

    // Ride Control errors (0x07, 0x08)
    var rcErrorCode: String = ""
    var rcNode2ErrorCode: String = ""

    // Motor / SyncDrive (0x09)
    var motorModel: String = ""
    var motorFwVersion: String = ""
    var motorHwVersion: String = ""
    var motorPSN: Int = 0

    // Motor errors (0x0B, 0x0C)
    var motorErrorCode1: String = ""
    var motorErrorCode2: String = ""

    // Service (0x0A)
    var serviceToolConnections: Int = 0
    var lastServiceHoursAgo: Int = 0
    var lastServiceKmAgo: Int = 0
    var avgAmpsBoost: Double = 0
    var avgAmpsPower: Double = 0
    var avgAmpsClimb: Double = 0
    var avgAmpsNormal: Double = 0
    var avgAmpsTour: Double = 0
    var avgAmpsEco: Double = 0

    // EnergyPak version (0x0D)
    var epVersion: String = ""

    // EnergyPak charge info (0x0E)
    var epChargeCycles: Int = 0
    var epChargeTimes: Int = 0
    var epDischargePercent: Int = 0

    // EnergyPak error (0x0F)
    var epErrorCode: String = ""

    // EnergyPak capacity (0x10)
    var epMaxNotChargedDays: Int = 0
    var epNotChargedCycles: Int = 0
    var epCapacityWh: Double = 0

    // Battery from ACTIVE_DATA_ENERGY_PAK_1 (0x13)
    var epCapacityPercent: Int = 0
    var epLifePercent: Int = 0
    var epLastFullCapacityWh: Double = 0

    // Mode usage % (0x06)
    var modeUsage: ModeUsageData = ModeUsageData()

    var lastUpdated: Date?
}

struct ModeUsageData: Codable, Equatable {
    var smart: Int = 0
    var boostPlus: Int = 0
    var boost: Int = 0
    var powerPlus: Int = 0
    var power: Int = 0
    var climbPlus: Int = 0
    var climb: Int = 0
    var normalPlus: Int = 0
    var normal: Int = 0
    var tourPlus: Int = 0
    var tour: Int = 0
    var eco: Int = 0
    var off: Int = 0

    var nonZeroModes: [(label: String, pct: Int)] {
        let all: [(String, Int)] = [
            ("Eco", eco), ("Normal", normal), ("Normal+", normalPlus),
            ("Tour", tour), ("Tour+", tourPlus),
            ("Power", power), ("Power+", powerPlus),
            ("Boost", boost), ("Boost+", boostPlus),
            ("Climb", climb), ("Climb+", climbPlus),
            ("Smart", smart), ("Off", off),
        ]
        return all.filter { $0.1 > 0 }
    }
}
