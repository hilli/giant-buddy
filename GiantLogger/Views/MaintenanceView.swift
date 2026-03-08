import SwiftUI
import SwiftData
import UserNotifications

struct MaintenanceView: View {
    @Query(filter: #Predicate<MaintenanceItem> { $0.isActive }, sort: \MaintenanceItem.componentName)
    private var activeComponents: [MaintenanceItem]

    @Query(sort: \ErrorLogEntry.date, order: .reverse)
    private var errorLog: [ErrorLogEntry]

    @Query(sort: \BatterySnapshot.date, order: .reverse)
    private var batterySnapshots: [BatterySnapshot]

    @EnvironmentObject var bikeService: GiantBikeService
    @Environment(\.modelContext) private var modelContext

    @State private var showAddSheet = false
    @State private var editingItem: MaintenanceItem?
    @AppStorage("maintenanceReminders") private var remindersEnabled = false

    private var currentOdo: Double {
        Double(bikeService.bikeInfo?.odo ?? 0)
    }

    var body: some View {
        List {
            componentsSection
            batterySection
            errorSection
        }
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddComponentSheet(currentOdo: currentOdo)
        }
        .sheet(item: $editingItem) { item in
            EditComponentSheet(item: item, currentOdo: currentOdo)
        }
    }

    // MARK: - Components Section

    private var componentsSection: some View {
        Section {
            if activeComponents.isEmpty {
                ContentUnavailableView(
                    "No Components",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Tap + to add a component to track its maintenance schedule.")
                )
            } else {
                ForEach(activeComponents) { item in
                    ComponentRow(item: item, currentOdo: currentOdo)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = item }
                        .swipeActions(edge: .leading) {
                            Button("Service") {
                                serviceComponent(item)
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                item.isActive = false
                            }
                        }
                }
            }

            Toggle("Service Reminders", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, enabled in
                    if enabled { requestNotificationPermission() }
                }
        } header: {
            Text("Components")
        } footer: {
            if remindersEnabled {
                // TODO: Notification scheduling not yet implemented
                Text("Notification reminders coming in a future update.")
            }
        }
    }

    // MARK: - Battery Section

    private var batterySection: some View {
        Section {
            if let latest = batterySnapshots.first {
                NavigationLink {
                    BatteryHealthView()
                        .environmentObject(bikeService)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Battery Health")
                                .font(.headline)
                            HStack(spacing: 12) {
                                Label("\(latest.healthPercent)%", systemImage: "heart.fill")
                                    .foregroundStyle(healthColor(latest.healthPercent))
                                Label("\(latest.chargeCycles) cycles", systemImage: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        Spacer()
                    }
                }
            } else {
                HStack {
                    Image(systemName: "battery.100")
                        .foregroundStyle(.secondary)
                    Text("Connect to your bike to record battery health data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Battery")
        }
    }

    // MARK: - Error Section

    private var errorSection: some View {
        Section {
            if errorLog.isEmpty {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("No error codes recorded.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(errorLog.prefix(10)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.source.capitalized)
                                .font(.subheadline.bold())
                            Text("Code: \(entry.errorCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.date, style: .date)
                                .font(.caption)
                            Text("\(Int(entry.odometer)) km")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Clear All", role: .destructive) {
                    for entry in errorLog {
                        modelContext.delete(entry)
                    }
                }
            }
        } header: {
            Text("Error History")
        }
    }

    // MARK: - Helpers

    private func serviceComponent(_ item: MaintenanceItem) {
        item.installDate = .now
        item.installOdometer = currentOdo
        item.notes += item.notes.isEmpty ? "Serviced \(Date.now.formatted(date: .abbreviated, time: .omitted))" : "\nServiced \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    }

    private func healthColor(_ percent: Int) -> Color {
        if percent > 80 { return .green }
        if percent > 60 { return .yellow }
        return .red
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if !granted {
                Task { @MainActor in
                    remindersEnabled = false
                }
            }
        }
    }
}

// MARK: - Component Row

struct ComponentRow: View {
    let item: MaintenanceItem
    let currentOdo: Double

    private var progress: Double { item.serviceProgress(currentOdo: currentOdo) }
    private var isDue: Bool { item.isServiceDue(currentOdo: currentOdo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.componentName)
                    .font(.headline)
                Spacer()
                if isDue {
                    Text("Service Due!")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }

            HStack(spacing: 12) {
                Label(item.installDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                Label(String(format: "%.0f km", item.kmSinceInstall(currentOdo: currentOdo)), systemImage: "road.lanes")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if item.serviceIntervalKm > 0 || item.serviceIntervalDays > 0 {
                ProgressView(value: min(progress, 1.0))
                    .tint(progressColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var progressColor: Color {
        if progress >= 1.0 { return .red }
        if progress >= 0.8 { return .yellow }
        return .green
    }
}

// MARK: - Add Component Sheet

struct AddComponentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currentOdo: Double

    @State private var componentName = ""
    @State private var intervalKm: Double = 0
    @State private var intervalDays: Int = 0
    @State private var customOdo: String = ""

    private var installOdo: Double {
        Double(customOdo) ?? currentOdo
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Component Name", text: $componentName)
                } header: {
                    Text("Component")
                }

                Section {
                    presetButton("Chain", km: 3000)
                    presetButton("Brake Pads", km: 5000)
                    presetButton("Tires", km: 8000)
                    presetButton("Battery Check", km: 0, days: 365)
                    presetButton("General Service", km: 5000, days: 365)
                } header: {
                    Text("Quick Add")
                }

                Section {
                    TextField("Service Interval (km)", value: $intervalKm, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Service Interval (days)", value: $intervalDays, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Install Odometer (km)", text: $customOdo, prompt: Text(String(format: "%.0f (current)", currentOdo)))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Custom Interval")
                }
            }
            .navigationTitle("Add Component")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addComponent() }
                        .disabled(componentName.isEmpty)
                }
            }
        }
    }

    private func presetButton(_ name: String, km: Double, days: Int = 0) -> some View {
        Button {
            let item = MaintenanceItem(
                componentName: name,
                installOdometer: currentOdo,
                serviceIntervalKm: km,
                serviceIntervalDays: days
            )
            modelContext.insert(item)
            dismiss()
        } label: {
            HStack {
                Text(name)
                Spacer()
                if km > 0 { Text("\(Int(km)) km").foregroundStyle(.secondary) }
                if days > 0 { Text("\(days) days").foregroundStyle(.secondary) }
            }
        }
    }

    private func addComponent() {
        let item = MaintenanceItem(
            componentName: componentName,
            installOdometer: installOdo,
            serviceIntervalKm: intervalKm,
            serviceIntervalDays: intervalDays
        )
        modelContext.insert(item)
        dismiss()
    }
}

// MARK: - Edit Component Sheet

struct EditComponentSheet: View {
    @Bindable var item: MaintenanceItem
    let currentOdo: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.componentName)
                } header: {
                    Text("Component")
                }

                Section {
                    TextField("Service Interval (km)", value: $item.serviceIntervalKm, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Service Interval (days)", value: $item.serviceIntervalDays, format: .number)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Intervals")
                }

                Section {
                    DatePicker("Install Date", selection: $item.installDate, displayedComponents: .date)
                    HStack {
                        Text("Install Odometer")
                        Spacer()
                        Text(String(format: "%.0f km", item.installOdometer))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Install Info")
                }

                Section {
                    HStack {
                        Text("Km Since Install")
                        Spacer()
                        Text(String(format: "%.0f km", item.kmSinceInstall(currentOdo: currentOdo)))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Days Since Install")
                        Spacer()
                        Text("\(item.daysSinceInstall) days")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Service Progress")
                        Spacer()
                        Text(String(format: "%.0f%%", item.serviceProgress(currentOdo: currentOdo) * 100))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    TextField("Notes", text: $item.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Component")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
