import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var rideRecorder: RideRecorder

    @AppStorage("autoRecord") private var autoRecord = true
    @AppStorage("recordingInterval") private var recordingInterval = 2.0
    @AppStorage("savedDeviceName") private var savedDeviceName = ""
    @AppStorage("savedDeviceID") private var savedDeviceID = ""

    @State private var showingShareSheet = false
    @State private var logSize = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-Record on Connect", isOn: $autoRecord)
                        .onChange(of: autoRecord) { _, newValue in
                            rideRecorder.autoRecord = newValue
                        }

                    Picker("Recording Interval", selection: $recordingInterval) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                    }
                    .onChange(of: recordingInterval) { _, newValue in
                        rideRecorder.recordingInterval = newValue
                    }
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Shorter intervals capture more detail but use more storage.")
                }

                Section {
                    if savedDeviceName.isEmpty {
                        Text("No saved device")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Device")
                            Spacer()
                            Text(savedDeviceName)
                                .foregroundStyle(.secondary)
                        }
                        Button("Forget Device", role: .destructive) {
                            savedDeviceName = ""
                            savedDeviceID = ""
                            bikeManager.autoConnectIdentifier = nil
                            UserDefaults.standard.set(false, forKey: "autoConnectEnabled")
                        }
                    }

                    Toggle("Auto-Connect", isOn: Binding(
                        get: { bikeManager.autoConnectIdentifier != nil },
                        set: { enabled in
                            if enabled, let id = UUID(uuidString: savedDeviceID) {
                                bikeManager.autoConnectIdentifier = id
                                UserDefaults.standard.set(true, forKey: "autoConnectEnabled")
                            } else {
                                bikeManager.autoConnectIdentifier = nil
                                UserDefaults.standard.set(false, forKey: "autoConnectEnabled")
                            }
                        }
                    ))
                    .disabled(savedDeviceID.isEmpty)
                } header: {
                    Text("Bluetooth")
                } footer: {
                    Text("When auto-connect is enabled, the app will automatically connect to your saved bike when it's in range.")
                }

                debugLogSection

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/hilli/giant-logger-ios")!) {
                        HStack {
                            Text("Source Code")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .onAppear { refreshLogSize() }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [DebugLogger.shared.logFileURL])
            }
        }
    }

    private var debugLogSection: some View {
        Section {
            HStack {
                Text("Log Size")
                Spacer()
                Text(formattedLogSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                showingShareSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Debug Log")
                }
            }
            .disabled(logSize == 0)

            Button("Clear Log", role: .destructive) {
                DebugLogger.shared.clearLog()
                refreshLogSize()
            }
            .disabled(logSize == 0)
        } header: {
            Text("Debug Log")
        } footer: {
            Text("BLE/GEV protocol logs are written to a file on device. Export and share to debug connectivity issues.")
        }
    }

    private func refreshLogSize() {
        logSize = DebugLogger.shared.logFileSize
    }

    private var formattedLogSize: String {
        if logSize == 0 { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(logSize))
    }
}
