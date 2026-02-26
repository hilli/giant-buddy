import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var bikeService: GiantBikeService

    var body: some View {
        NavigationStack {
            List {
                // Status section
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
                } header: {
                    Text("Connection")
                }

                // Bike info
                if bikeService.isGevConnected {
                    bikeInfoSection
                }

                // Scan & discovered devices
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
            .navigationTitle("Connection")
        }
    }

    @ViewBuilder
    private var bikeInfoSection: some View {
        Section {
            if let factory = bikeService.factoryData {
                InfoRow(label: "Frame", value: factory.frameNumber)
            }
            if let sync = bikeService.syncDriveData {
                InfoRow(label: "Odometer", value: "\(sync.odometer) km")
                InfoRow(label: "Motor FW", value: sync.firmwareVersion)
            }
            if let energy = bikeService.energyPakData {
                InfoRow(label: "Battery Health", value: "\(energy.lifePercent)%")
                InfoRow(label: "Battery FW", value: energy.firmwareVersion)
            }
        } header: {
            Text("Bike Info")
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
