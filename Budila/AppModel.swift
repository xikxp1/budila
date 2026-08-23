import AlarmKit
import AVFoundation
import SwiftUI
import UIKit

enum ScannerPurpose: Identifiable, Equatable {
    case enroll
    case dismiss(UUID)

    var id: String {
        switch self {
        case .enroll: "enroll"
        case .dismiss(let id): "dismiss-\(id.uuidString)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data = BudilaStore().load()
    @Published private(set) var alarmAuthorization = AlarmManager.shared.authorizationState
    @Published private(set) var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var alarmStates: [UUID: Alarm.State] = [:]
    @Published var scannerPurpose: ScannerPurpose?
    @Published var message: String?

    private let store = BudilaStore()
    private var alarmUpdatesTask: Task<Void, Never>?

    var onboardingComplete: Bool {
        alarmAuthorization == .authorized && cameraAuthorization == .authorized && data.qrDigest != nil
    }

    var hasActiveAlarm: Bool {
        alarmStates.values.contains { $0 == .alerting || $0 == .countdown || $0 == .paused }
    }

    var scannerAvailable: Bool {
        cameraAuthorization == .authorized
            && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    init() {
        alarmUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await alarms in AlarmManager.shared.alarmUpdates {
                self.alarmStates = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0.state) })
            }
        }
        refresh()
    }

    func refresh() {
        data = store.load()
        alarmAuthorization = AlarmManager.shared.authorizationState
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        do {
            let alarms = try AlarmManager.shared.alarms
            alarmStates = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0.state) })
        } catch {
            message = error.localizedDescription
        }
        if let rootID = data.pendingScanRootID {
            scannerPurpose = .dismiss(rootID)
        }
    }

    func requestAlarmAuthorization() async {
        do {
            alarmAuthorization = try await AlarmManager.shared.requestAuthorization()
        } catch {
            message = error.localizedDescription
        }
    }

    func requestCameraAuthorization() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func beginEnrollment() {
        guard !hasActiveAlarm else {
            message = "Finish the active alarm before replacing the QR code."
            return
        }
        scannerPurpose = .enroll
    }

    func handleScannedPayload(_ payload: String) -> Bool {
        switch scannerPurpose {
        case .enroll:
            data = store.update { $0.qrDigest = QRCodeDigest.make(payload) }
            scannerPurpose = nil
            return true
        case .dismiss(let rootID):
            guard QRCodeDigest.matches(payload, digest: data.qrDigest) else {
                message = "That QR code does not match."
                return false
            }
            if finishAlarm(rootID: rootID) { scannerPurpose = nil }
            return scannerPurpose == nil
        case nil:
            return false
        }
    }

    func emergencyStop() {
        guard case .dismiss(let rootID) = scannerPurpose else { return }
        if finishAlarm(rootID: rootID) { scannerPurpose = nil }
    }

    func save(_ alarm: AlarmDefinition) async {
        guard !alarm.weekdays.isEmpty else {
            message = "Choose at least one weekday."
            return
        }
        do {
            try AlarmScheduler.cancel(alarm.id)
        } catch {
            message = error.localizedDescription
            refresh()
            return
        }
        do {
            if alarm.enabled { try await AlarmScheduler.schedule(alarm) }
            data = store.update { $0.upsert(alarm) }
            refresh()
        } catch {
            var failed = alarm
            failed.enabled = false
            data = store.update { $0.upsert(failed) }
            message = error.localizedDescription
            refresh()
        }
    }

    func setEnabled(_ alarm: AlarmDefinition, enabled: Bool) async {
        var updated = alarm
        updated.enabled = enabled
        await save(updated)
    }

    func delete(_ alarm: AlarmDefinition) {
        do {
            data = try store.update { data in
                var alarmIDs = Set([alarm.id])
                if let session = data.sessions.first(where: { $0.rootAlarmID == alarm.id }) {
                    alarmIDs.insert(session.activeAlarmID)
                    if let guardID = session.guardAlarmID { alarmIDs.insert(guardID) }
                }
                for id in alarmIDs { try AlarmScheduler.cancel(id) }
                data.alarms.removeAll { $0.id == alarm.id }
                data.sessions.removeAll { $0.rootAlarmID == alarm.id }
                if data.pendingScanRootID == alarm.id { data.pendingScanRootID = nil }
            }
            refresh()
        } catch {
            message = error.localizedDescription
            refresh()
        }
    }

    private func finishAlarm(rootID: UUID) -> Bool {
        do {
            data = try store.update { data in
                if let session = data.sessions.first(where: { $0.rootAlarmID == rootID }) {
                    switch session.kind {
                    case .snoozed:
                        try AlarmScheduler.stop(session.activeAlarmID)
                    case .guardAlarm:
                        try AlarmScheduler.cancel(session.activeAlarmID)
                    }
                    if let guardID = session.guardAlarmID, guardID != session.activeAlarmID {
                        try AlarmScheduler.cancel(guardID)
                    }
                } else if let state = alarmStates[rootID], state == .alerting || state == .countdown || state == .paused {
                    try AlarmScheduler.stop(rootID)
                }
                _ = data.completeScan(rootAlarmID: rootID)
            }
            refresh()
            return true
        } catch {
            message = error.localizedDescription
            refresh()
            return false
        }
    }
}
