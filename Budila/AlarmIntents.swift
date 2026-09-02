import AlarmKit
import AppIntents

struct ScanToStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Scan to Stop"
    static let description = IntentDescription("Opens Budila and waits for the enrolled QR code.")
    static let openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Alarm ID") var alarmID: String
    @Parameter(title: "Root alarm ID") var rootAlarmID: String
    @Parameter(title: "Label") var label: String

    init(alarmID: String, rootAlarmID: String, label: String) {
        self.alarmID = alarmID
        self.rootAlarmID = rootAlarmID
        self.label = label
    }

    init() {
        alarmID = ""
        rootAlarmID = ""
        label = "Alarm"
    }

    func perform() async throws -> some IntentResult {
        guard let rootID = UUID(uuidString: rootAlarmID) else { return .result() }
        let store = BudilaStore()
        let alarm = store.load().alarms.first { $0.id == rootID }
        let guardID = UUID()
        let guardScheduled: Bool
        do {
            try await AlarmScheduler.scheduleGuard(
                id: guardID,
                rootAlarmID: rootID,
                label: label,
                alarm: alarm
            )
            guardScheduled = true
        } catch {
            guardScheduled = false
        }

        store.update { data in
            let used = data.sessions.first(where: { $0.rootAlarmID == rootID })?.snoozesUsed ?? 0
            if guardScheduled {
                data.upsert(AlarmSession(
                    rootAlarmID: rootID,
                    activeAlarmID: guardID,
                    guardAlarmID: guardID,
                    snoozesUsed: used,
                    kind: .guardAlarm
                ))
            }
            data.enqueueScan(rootAlarmID: rootID)
        }
        return .result()
    }
}

struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze"
    static let description = IntentDescription("Snoozes a Budila alarm for three minutes.")
    static let openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Alarm ID") var alarmID: String
    @Parameter(title: "Root alarm ID") var rootAlarmID: String

    init(alarmID: String, rootAlarmID: String) {
        self.alarmID = alarmID
        self.rootAlarmID = rootAlarmID
    }

    init() {
        alarmID = ""
        rootAlarmID = ""
    }

    func perform() async throws -> some IntentResult {
        guard let alarmID = UUID(uuidString: alarmID),
              let rootID = UUID(uuidString: rootAlarmID) else { return .result() }

        let store = BudilaStore()
        store.update { data in
            let used = data.sessions.first(where: { $0.rootAlarmID == rootID })?.snoozesUsed ?? 0
            if SnoozeLimit.allows(used) {
                if (try? AlarmManager.shared.countdown(id: alarmID)) != nil {
                    data.upsert(AlarmSession(
                        rootAlarmID: rootID,
                        activeAlarmID: alarmID,
                        guardAlarmID: nil,
                        snoozesUsed: used + 1,
                        kind: .snoozed
                    ))
                }
            }
            data.enqueueScan(rootAlarmID: rootID)
        }
        return .result()
    }
}
