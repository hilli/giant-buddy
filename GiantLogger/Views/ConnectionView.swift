import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var bikeService: GiantBikeService

    var body: some View {
        NavigationStack {
            List {
                // Connection
                connectionSection

                // Bike data (from cache or live)
                if let info = bikeService.bikeInfo {
                    overviewSection(info)

                    // Maintenance Tracker
                    maintenanceSection

                    batterySection(info)
                    motorSection(info)
                    rideControlSection(info)
                    modeUsageSection(info)
                    serviceSection(info)
                }

                // Factory data
                if let factory = bikeService.factoryData {
                    factorySection(factory)
                }

                // Scan & devices
                scanSection
            }
            .navigationTitle("Bike")
            .refreshable {
                bikeService.fetchAllBikeData()
                try? await Task.sleep(for: .seconds(7))
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(bikeManager.connectionState.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
            }

            if bikeManager.connectionState == .connected {
                if let name = bikeManager.connectedPeripheralName {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Disconnect", role: .destructive) {
                    bikeService.sendDisconnect()
                    bikeManager.disconnect()
                }
            }

            if bikeService.isFetchingBikeInfo {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching bike data…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else if let updated = bikeService.bikeInfo?.lastUpdated {
                HStack {
                    Text("Last Updated")
                    Spacer()
                    Text(updated, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Connection")
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        Section {
            NavigationLink {
                MaintenanceView()
                    .environmentObject(bikeService)
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.blue)
                    Text("Maintenance Tracker")
                    Spacer()
                }
            }
        } header: {
            Text("Maintenance")
        }
    }

    // MARK: - Overview

    private func overviewSection(_ info: BikeInfo) -> some View {
        Section {
            InfoRow(label: "Odometer", value: "\(info.odo) km")
            InfoRow(label: "Total Usage", value: "\(info.totalUsageHours) hours")
        } header: {
            Text("Overview")
        }
    }

    // MARK: - Battery

    private func batterySection(_ info: BikeInfo) -> some View {
        Section {
            InfoRow(label: "Charge", value: "\(info.epCapacityPercent)%")
            InfoRow(label: "Health", value: "\(info.epLifePercent)%")
            InfoRow(label: "Last Full Capacity", value: String(format: "%.1f Wh", info.epLastFullCapacityWh))
            if info.epCapacityWh > 0 {
                InfoRow(label: "Design Capacity", value: String(format: "%.1f Wh", info.epCapacityWh))
            }
            InfoRow(label: "Charge Cycles", value: "\(info.epChargeCycles)")
            InfoRow(label: "Total Charges", value: "\(info.epChargeTimes)")
            if info.epDischargePercent > 0 {
                InfoRow(label: "Discharge", value: "\(info.epDischargePercent)%")
            }
            if info.epMaxNotChargedDays > 0 {
                InfoRow(label: "Max Days Not Charged", value: "\(info.epMaxNotChargedDays)")
            }
            if !info.epVersion.isEmpty {
                InfoRow(label: "Version", value: info.epVersion)
            }
            if !info.epErrorCode.isEmpty && !info.epErrorCode.allSatisfy({ $0 == "0" }) {
                InfoRow(label: "Error Code", value: info.epErrorCode)
            }
        } header: {
            Text("Battery")
        }
    }

    // MARK: - Motor

    private func motorSection(_ info: BikeInfo) -> some View {
        Section {
            if !info.motorModel.isEmpty {
                InfoRow(label: "Model", value: info.motorModel)
            }
            if !info.motorFwVersion.isEmpty {
                InfoRow(label: "Firmware", value: info.motorFwVersion)
            }
            if !info.motorHwVersion.isEmpty {
                InfoRow(label: "Hardware", value: info.motorHwVersion)
            }
            if !info.motorErrorCode1.isEmpty && !info.motorErrorCode1.allSatisfy({ $0 == "0" }) {
                InfoRow(label: "Error Code 1", value: info.motorErrorCode1)
            }
            if !info.motorErrorCode2.isEmpty && !info.motorErrorCode2.allSatisfy({ $0 == "0" }) {
                InfoRow(label: "Error Code 2", value: info.motorErrorCode2)
            }
        } header: {
            Text("Motor")
        }
    }

    // MARK: - Ride Control

    private func rideControlSection(_ info: BikeInfo) -> some View {
        Section {
            if !info.rcFwVersion.isEmpty {
                InfoRow(label: "Firmware", value: info.rcFwVersion)
            }
            if !info.rcHwVersion.isEmpty {
                InfoRow(label: "Hardware", value: info.rcHwVersion)
            }
            if !info.rcErrorCode.isEmpty && !info.rcErrorCode.allSatisfy({ $0 == "0" }) {
                InfoRow(label: "Error Code", value: info.rcErrorCode)
            }
            if !info.rcNode2ErrorCode.isEmpty && !info.rcNode2ErrorCode.allSatisfy({ $0 == "0" }) {
                InfoRow(label: "Node 2 Error", value: info.rcNode2ErrorCode)
            }
        } header: {
            Text("Ride Control")
        }
    }

    // MARK: - Mode Usage

    @ViewBuilder
    private func modeUsageSection(_ info: BikeInfo) -> some View {
        let modes = info.modeUsage.nonZeroModes
        if !modes.isEmpty {
            Section {
                ForEach(modes, id: \.label) { mode in
                    HStack {
                        Text(mode.label)
                        Spacer()
                        Text("\(mode.pct)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Mode Usage")
            }
        }
    }

    // MARK: - Service

    @ViewBuilder
    private func serviceSection(_ info: BikeInfo) -> some View {
        if info.serviceToolConnections > 0 || info.lastServiceHoursAgo > 0 {
            Section {
                InfoRow(label: "Service Connections", value: "\(info.serviceToolConnections)")
                if info.lastServiceHoursAgo > 0 {
                    InfoRow(label: "Hours Since Service", value: "\(info.lastServiceHoursAgo)")
                }
                if info.lastServiceKmAgo > 0 {
                    InfoRow(label: "Km Since Service", value: "\(info.lastServiceKmAgo)")
                }
            } header: {
                Text("Service")
            }
        }
    }

    // MARK: - Factory

    private func factorySection(_ factory: FactoryData) -> some View {
        Section {
            InfoRow(label: "Frame", value: factory.frameNumber)
            InfoRow(label: "Speed Limit", value: String(format: "%.1f km/h", Double(factory.speedLimitation) / 10.0))
            InfoRow(label: "Wheel Circ.", value: "\(factory.circumference) mm")
        } header: {
            Text("Factory")
        }
    }

    // MARK: - Scan

    private var scanSection: some View {
        Section {
            if bikeManager.connectionState == .disconnected || bikeManager.connectionState == .scanning {
                Button {
                    bikeManager.startScan()
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(bikeManager.connectionState == .scanning ? "Scanning…" : "Scan for Bikes")
                    }
                }
                .disabled(bikeManager.connectionState == .scanning)
            }

            ForEach(bikeManager.discoveredDevices, id: \.peripheral.identifier) { device in
                Button {
                    bikeManager.connect(to: device.peripheral)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(device.peripheral.identifier.uuidString)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text("Devices")
        }
    }

    private var statusColor: Color {
        switch bikeManager.connectionState {
        case .connected: .green
        case .connecting, .discoveringServices: .orange
        case .scanning: .blue
        case .disconnected: .gray
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
