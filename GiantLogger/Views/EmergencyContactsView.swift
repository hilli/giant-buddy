import SwiftUI

/// Settings view for managing emergency contacts and crash detection preferences.
struct EmergencyContactsView: View {
    @AppStorage("crashDetectionEnabled") private var crashDetectionEnabled = false

    @State private var contacts: [EmergencyContact] = []
    @State private var editingContact: EmergencyContact?
    @State private var isAddingNew = false
    @State private var showTestAlert = false

    @StateObject private var testCrashDetector = CrashDetector()
    @EnvironmentObject var locationManager: LocationManager

    private let maxContacts = 3

    var body: some View {
        Form {
            Section {
                Toggle("Enable Crash Detection", isOn: $crashDetectionEnabled)
            } header: {
                Text("Crash Detection")
            } footer: {
                Text("When enabled, the app monitors for sudden impacts while riding. If a crash is detected and you don't respond within 60 seconds, an SMS is sent to your emergency contacts with your GPS location.")
            }

            Section {
                if contacts.isEmpty {
                    Text("No emergency contacts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contacts) { contact in
                        Button {
                            editingContact = contact
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                        .foregroundStyle(.primary)
                                    Text(contact.phone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: deleteContacts)
                }

                if contacts.count < maxContacts {
                    Button {
                        isAddingNew = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("Add Contact")
                        }
                    }
                }
            } header: {
                Text("Emergency Contacts")
            } footer: {
                Text("Up to \(maxContacts) contacts. These people will receive an SMS with your location if a crash is detected.")
            }

            Section {
                Button {
                    testCrashDetector.triggerTestAlert()
                    showTestAlert = true
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.orange)
                        Text("Test Crash Alert")
                    }
                }
                .disabled(contacts.isEmpty && crashDetectionEnabled)
            } footer: {
                Text("Simulates a crash detection countdown. No SMS will be sent.")
            }
        }
        .navigationTitle("Emergency Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadContacts() }
        .sheet(item: $editingContact) { contact in
            ContactEditorSheet(contact: contact) { updated in
                if let idx = contacts.firstIndex(where: { $0.id == updated.id }) {
                    contacts[idx] = updated
                    saveContacts()
                }
            }
        }
        .sheet(isPresented: $isAddingNew) {
            ContactEditorSheet(contact: nil) { newContact in
                contacts.append(newContact)
                saveContacts()
            }
        }
        .fullScreenCover(isPresented: $showTestAlert) {
            CrashAlertView(crashDetector: testCrashDetector)
                .environmentObject(locationManager)
                .onDisappear { showTestAlert = false }
        }
        .onChange(of: testCrashDetector.isCrashDetected) { _, detected in
            if !detected { showTestAlert = false }
        }
    }

    private func loadContacts() {
        contacts = CrashDetector.loadEmergencyContacts()
    }

    private func saveContacts() {
        CrashDetector.saveEmergencyContacts(contacts)
    }

    private func deleteContacts(at offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
        saveContacts()
    }
}

// MARK: - Contact Editor Sheet

/// Sheet for adding or editing a single emergency contact.
private struct ContactEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var phone: String
    private let existingID: UUID?
    private let onSave: (EmergencyContact) -> Void

    init(contact: EmergencyContact?, onSave: @escaping (EmergencyContact) -> Void) {
        _name = State(initialValue: contact?.name ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        existingID = contact?.id
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    TextField("Phone Number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle(existingID == nil ? "Add Contact" : "Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var contact = EmergencyContact(name: name.trimmingCharacters(in: .whitespaces),
                                                       phone: phone.trimmingCharacters(in: .whitespaces))
                        if let id = existingID { contact.id = id }
                        onSave(contact)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              phone.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
