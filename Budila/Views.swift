import AlarmKit
import AVFoundation
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.onboardingComplete {
                AlarmListView()
            } else {
                OnboardingView()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(item: $model.scannerPurpose) { purpose in
            ScannerScreen(
                purpose: purpose,
                isAvailable: model.scannerAvailable,
                message: $model.message,
                onScan: model.handleScannedPayload,
                onEmergencyRecovery: { Task { await model.emergencyRecovery() } },
                onOpenSettings: model.openSettings
            )
            .id(purpose.id)
        }
        .alert("Budila", isPresented: Binding(
            get: { model.scannerPurpose == nil && model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Budila")
                    .font(.largeTitle.bold())
                Text("An alarm that sends you to your QR code.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 14) {
                SetupRow(title: "Allow alarms", complete: model.alarmAuthorization == .authorized) {
                    if model.alarmAuthorization == .denied {
                        model.openSettings()
                    } else {
                        Task { await model.requestAlarmAuthorization() }
                    }
                }
                SetupRow(title: "Allow camera", complete: model.cameraAuthorization == .authorized) {
                    if model.cameraAuthorization == .denied || model.cameraAuthorization == .restricted {
                        model.openSettings()
                    } else {
                        Task { await model.requestCameraAuthorization() }
                    }
                }
                SetupRow(title: "Enroll QR code", complete: model.data.qrDigest != nil) {
                    model.beginEnrollment()
                }
                .disabled(model.alarmAuthorization != .authorized || model.cameraAuthorization != .authorized)
            }
            Spacer()
        }
        .padding(28)
    }
}

private struct SetupRow: View {
    let title: String
    let complete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(complete ? .green : .orange)
                Text(title)
                Spacer()
                if !complete { Image(systemName: "chevron.right") }
            }
            .padding()
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityValue(complete ? "Complete" : "Required")
    }
}

struct AlarmListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingAlarm: AlarmDefinition?

    var body: some View {
        NavigationStack {
            Group {
                if model.data.alarms.isEmpty {
                    ContentUnavailableView(
                        "No alarms",
                        systemImage: "alarm",
                        description: Text("Add an alarm and choose the days it should ring.")
                    )
                } else {
                    List {
                        ForEach(model.data.alarms) { alarm in
                            AlarmRow(
                                alarm: alarm,
                                onEdit: { editingAlarm = alarm },
                                onToggle: { enabled in Task { await model.setEnabled(alarm, enabled: enabled) } }
                            )
                            .disabled(model.isBusy(alarm.id))
                            .swipeActions {
                                if !model.isBusy(alarm.id) {
                                    Button("Delete", role: .destructive) { model.delete(alarm) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingAlarm = AlarmDefinition()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add alarm")
                }
            }
        }
        .sheet(item: $editingAlarm) { alarm in
            AlarmEditor(alarm: alarm) { updated in
                Task { await model.save(updated) }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingEmergencyRecovery = false

    var body: some View {
        Form {
            Section {
                Button {
                    model.beginEnrollment()
                } label: {
                    Label("Replace QR Code", systemImage: "qrcode.viewfinder")
                }
                .disabled(model.hasActiveAlarm)
            } header: {
                Text("QR Code")
            } footer: {
                if model.hasActiveAlarm {
                    Text("Finish the active alarm before replacing the QR code.")
                }
            }

            Section("Emergency Recovery") {
                Text("Stops every Budila alarm, clears the enrolled QR code, and disables all alarms until you enroll a new code.")
                Button("Emergency Recovery", role: .destructive) {
                    showingEmergencyRecovery = true
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset QR and Pause All Alarms?",
            isPresented: $showingEmergencyRecovery,
            titleVisibility: .visible
        ) {
            Button("Reset QR and Pause All Alarms", role: .destructive) {
                Task { await model.emergencyRecovery() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops every Budila alarm, clears the enrolled QR code, and disables all alarms. You will need to enroll a new QR code and turn alarms back on.")
        }
    }
}

private struct AlarmRow: View {
    let alarm: AlarmDefinition
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(alarm.time, format: .dateTime.hour().minute())
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundStyle(alarm.enabled ? .primary : .secondary)
                    Text("\(alarm.displayLabel) · \(alarm.daysDescription)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { onToggle($0) }))
                .labelsHidden()
                .accessibilityLabel("Enable \(alarm.displayLabel)")
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }
}

struct AlarmEditor: View {
    @State private var alarm: AlarmDefinition
    @State private var time: Date
    let onSave: (AlarmDefinition) -> Void
    @Environment(\.dismiss) private var dismiss

    init(alarm: AlarmDefinition, onSave: @escaping (AlarmDefinition) -> Void) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: alarm.time)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Section("Label") {
                    TextField("Alarm", text: $alarm.label)
                }
                Section("Repeat") {
                    HStack {
                        ForEach(BudilaWeekday.allCases) { day in
                            Button(String(day.shortName.prefix(1))) {
                                if alarm.weekdays.contains(day) {
                                    alarm.weekdays.remove(day)
                                } else {
                                    alarm.weekdays.insert(day)
                                }
                            }
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(alarm.weekdays.contains(day) ? .black : .orange)
                            .background(alarm.weekdays.contains(day) ? Color.orange : Color.orange.opacity(0.14), in: Circle())
                            .buttonStyle(.plain)
                            .accessibilityLabel(day.shortName)
                            .accessibilityAddTraits(alarm.weekdays.contains(day) ? .isSelected : [])
                        }
                    }
                    if alarm.weekdays.isEmpty {
                        Text("Choose at least one day.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        alarm.hour = components.hour ?? 7
                        alarm.minute = components.minute ?? 0
                        onSave(alarm)
                        dismiss()
                    }
                    .disabled(alarm.weekdays.isEmpty)
                }
            }
        }
    }
}
