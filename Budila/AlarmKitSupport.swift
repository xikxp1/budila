import AlarmKit
import SwiftUI

enum AlarmScheduler {
    typealias Configuration = AlarmManager.AlarmConfiguration<BudilaAlarmMetadata>

    static func schedule(_ alarm: AlarmDefinition) async throws {
        let weekdays = BudilaWeekday.allCases
            .filter(alarm.weekdays.contains)
            .map(\.alarmKitValue)
        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: .weekly(weekdays)))
        let configuration = makeConfiguration(
            schedule: schedule,
            alarmID: alarm.id,
            rootAlarmID: alarm.id,
            label: alarm.displayLabel
        )
        try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
    }

    static func scheduleGuard(id: UUID, rootAlarmID: UUID, label: String) async throws {
        let configuration = makeConfiguration(
            schedule: .fixed(.now.addingTimeInterval(10)),
            alarmID: id,
            rootAlarmID: rootAlarmID,
            label: label
        )
        try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func cancel(_ id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }

    static func stop(_ id: UUID) {
        try? AlarmManager.shared.stop(id: id)
    }

    private static func makeConfiguration(
        schedule: Alarm.Schedule,
        alarmID: UUID,
        rootAlarmID: UUID,
        label: String
    ) -> Configuration {
        let title = LocalizedStringResource(
            String.LocalizationValue(stringLiteral: label),
            bundle: .main
        )
        let stopButton = AlarmButton(
            text: "Scan to Stop",
            textColor: .white,
            systemImageName: "qrcode.viewfinder"
        )
        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "zzz"
        )
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .custom
        )
        let countdown = AlarmPresentation.Countdown(title: "Snoozed")
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert, countdown: countdown),
            metadata: BudilaAlarmMetadata(rootAlarmID: rootAlarmID.uuidString, label: label),
            tintColor: .orange
        )
        return Configuration(
            countdownDuration: .init(preAlert: nil, postAlert: 180),
            schedule: schedule,
            attributes: attributes,
            stopIntent: ScanToStopIntent(
                alarmID: alarmID.uuidString,
                rootAlarmID: rootAlarmID.uuidString,
                label: label
            ),
            secondaryIntent: SnoozeAlarmIntent(
                alarmID: alarmID.uuidString,
                rootAlarmID: rootAlarmID.uuidString
            ),
            sound: .named("alarm.caf")
        )
    }
}
