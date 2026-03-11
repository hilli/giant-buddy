import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bikeManager: BikeManager
    @EnvironmentObject var rideRecorder: RideRecorder
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var navigationEngine: NavigationEngine

    @AppStorage("autoRecord") private var autoRecord = true
    @AppStorage("recordingInterval") private var recordingInterval = 2.0
    @AppStorage("logWorkouts") private var logWorkouts = false
    @AppStorage("savedDeviceName") private var savedDeviceName = ""
    @AppStorage("savedDeviceID") private var savedDeviceID = ""
    @AppStorage("crashDetectionEnabled") private var crashDetectionEnabled = false

    @State private var showingShareSheet = false
    @State private var logSize = 0

    @State private var debugLogEnabled = DebugLogger.shared.isEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-Record on Connect", isOn: $autoRecord)
                        .onChange(of: autoRecord) { _, newValue in
                            rideRecorder.autoRecord = newValue
                        }

                    Toggle("Log to Apple Fitness", isOn: $logWorkouts)
                        .onChange(of: logWorkouts) { _, enabled in
                            if enabled { workoutManager.requestAuthorization() }
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
                    Text("When enabled, rides are saved as Outdoor Cycle workouts in Apple Health.")
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

                navigationSection

                stravaSection

                safetySection

                debugLogSection

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Author")
                        Spacer()
                        Text("Jens Hilligsøe")
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

    private var navigationSection: some View {
        Section {
            Toggle("Voice Guidance", isOn: Binding(
                get: { navigationEngine.voiceGuidanceEnabled },
                set: { enabled in
                    navigationEngine.voiceGuidanceEnabled = enabled
                    if !enabled { navigationEngine.stopVoice() }
                }
            ))

            Toggle("Haptic Feedback", isOn: Binding(
                get: { navigationEngine.hapticFeedbackEnabled },
                set: { navigationEngine.hapticFeedbackEnabled = $0 }
            ))
        } header: {
            Text("Navigation")
        } footer: {
            Text("Voice and haptic alerts for upcoming turns during navigation.")
        }
    }

    private var stravaSection: some View {
        Section {
            if stravaService.isConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Connected")
                            .font(.body)
                        if let name = stravaService.athleteName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                Toggle("Auto-Upload Rides", isOn: Binding(
                    get: { stravaService.autoUpload },
                    set: { stravaService.autoUpload = $0 }
                ))

                Button("Disconnect from Strava", role: .destructive) {
                    stravaService.disconnect()
                }
            } else {
                Button {
                    stravaService.authenticate()
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect to Strava")
                    }
                }
            }

            if let error = stravaService.lastUploadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Strava")
        } footer: {
            if stravaService.isConnected {
                Text("When auto-upload is enabled, rides are uploaded to Strava as e-bike rides when recording stops.")
            } else {
                Text("Connect your Strava account to upload rides.")
            }
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink {
                EmergencyContactsView()
            } label: {
                HStack {
                    Image(systemName: "shield.checkered")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text("Emergency Contacts & Crash Detection")
                        if crashDetectionEnabled {
                            Text("Enabled • \(emergencyContactCount) contact(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Safety")
        } footer: {
            Text("Crash detection monitors for sudden impacts while riding and can alert your emergency contacts.")
        }
    }

    private var emergencyContactCount: Int {
        CrashDetector.loadEmergencyContacts().count
    }

    private var debugLogSection: some View {
        Section {
            Toggle("Enable Debug Log", isOn: $debugLogEnabled)
                .onChange(of: debugLogEnabled) { _, newValue in
                    DebugLogger.shared.isEnabled = newValue
                }

            if debugLogEnabled {
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
            }
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
