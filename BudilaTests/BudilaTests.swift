import XCTest
@testable import Budila

final class BudilaTests: XCTestCase {
    func testPersistenceAndAlarmOrdering() throws {
        let suite = "BudilaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BudilaStore(defaults: defaults)

        var data = PersistedData()
        data.upsert(AlarmDefinition(hour: 9, minute: 30, label: "Late"))
        data.upsert(AlarmDefinition(hour: 6, minute: 45, label: "Early"))
        store.save(data)

        XCTAssertEqual(store.load().alarms.map(\.label), ["Early", "Late"])
    }

    func testQRCodeMatchingIsExact() {
        let digest = QRCodeDigest.make("budila-bedroom-code")
        XCTAssertTrue(QRCodeDigest.matches("budila-bedroom-code", digest: digest))
        XCTAssertFalse(QRCodeDigest.matches("Budila-bedroom-code", digest: digest))
        XCTAssertFalse(QRCodeDigest.matches("budila-bedroom-code ", digest: digest))
    }

    func testWeekdaysMapToAlarmKitWeekdays() {
        XCTAssertEqual(BudilaWeekday.allCases.map(\.alarmKitValue), [
            .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
        ])
    }

    func testOnlyTwoSnoozesAreAllowed() {
        XCTAssertTrue(SnoozeLimit.allows(0))
        XCTAssertTrue(SnoozeLimit.allows(1))
        XCTAssertFalse(SnoozeLimit.allows(2))
    }

    func testGuardUsesRemainingSnoozeSlotsThenOneMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let alarm = AlarmDefinition(hour: 8, minute: 0)
        let date: (Int, Int) -> Date = { minute, second in
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 24,
                hour: 8,
                minute: minute,
                second: second
            ))!
        }

        XCTAssertEqual(alarm.nextGuardDate(after: date(2, 0), calendar: calendar), date(3, 0))
        XCTAssertEqual(alarm.nextGuardDate(after: date(3, 0), calendar: calendar), date(6, 0))
        XCTAssertEqual(alarm.nextGuardDate(after: date(5, 59), calendar: calendar), date(6, 0))
        XCTAssertEqual(alarm.nextGuardDate(after: date(6, 0), calendar: calendar), date(7, 0))
        XCTAssertEqual(alarm.nextGuardDate(after: date(7, 0), calendar: calendar), date(8, 0))
    }

    func testCompletingScanRemovesGuardSession() {
        let rootID = UUID()
        let guardID = UUID()
        var data = PersistedData(
            sessions: [AlarmSession(
                rootAlarmID: rootID,
                activeAlarmID: guardID,
                guardAlarmID: guardID,
                snoozesUsed: 2,
                kind: .guardAlarm
            )],
            pendingScanRootIDs: [rootID]
        )

        let session = data.completeScan(rootAlarmID: rootID)

        XCTAssertEqual(session?.guardAlarmID, guardID)
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertNil(data.pendingScanRootID)
    }

    func testCompletingScanKeepsAnotherPendingAlarm() {
        let completedID = UUID()
        let pendingID = UUID()
        var data = PersistedData(
            sessions: [AlarmSession(
                rootAlarmID: completedID,
                activeAlarmID: UUID(),
                guardAlarmID: nil,
                snoozesUsed: 0,
                kind: .snoozed
            )],
            pendingScanRootIDs: [pendingID]
        )

        _ = data.completeScan(rootAlarmID: completedID)

        XCTAssertEqual(data.pendingScanRootID, pendingID)
    }

    func testRemovalListsEveryAlarmIDRootLastAndClearsState() {
        let rootID = UUID()
        let activeID = UUID()
        let guardID = UUID()
        var data = PersistedData(
            sessions: [AlarmSession(
                rootAlarmID: rootID,
                activeAlarmID: activeID,
                guardAlarmID: guardID,
                snoozesUsed: 1,
                kind: .guardAlarm
            )],
            pendingScanRootIDs: [rootID]
        )

        let alarmIDs = data.alarmIDsForRemoval(rootAlarmID: rootID)
        data.removeSession(for: rootID)

        XCTAssertEqual(Set(alarmIDs), Set([rootID, activeID, guardID]))
        XCTAssertEqual(alarmIDs.last, rootID)
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertNil(data.pendingScanRootID)
    }

    func testEmergencyResetDisablesAlarmsAndClearsQRState() {
        let rootID = UUID()
        let guardID = UUID()
        var data = PersistedData(
            alarms: [
                AlarmDefinition(hour: 6, minute: 30, label: "Early", enabled: true),
                AlarmDefinition(hour: 9, minute: 0, label: "Late", enabled: false),
            ],
            qrDigest: QRCodeDigest.make("lost-code"),
            sessions: [AlarmSession(
                rootAlarmID: rootID,
                activeAlarmID: guardID,
                guardAlarmID: guardID,
                snoozesUsed: 2,
                kind: .guardAlarm
            )],
            pendingScanRootIDs: [rootID]
        )
        var expectedAlarms = data.alarms
        for index in expectedAlarms.indices { expectedAlarms[index].enabled = false }

        data.resetForEmergency()

        XCTAssertEqual(data.alarms, expectedAlarms)
        XCTAssertNil(data.qrDigest)
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertTrue(data.pendingScanRootIDs.isEmpty)
    }

    func testPendingScansRemainInArrivalOrder() {
        let first = UUID()
        let second = UUID()
        var data = PersistedData()

        data.enqueueScan(rootAlarmID: first)
        data.enqueueScan(rootAlarmID: second)
        data.enqueueScan(rootAlarmID: first)
        _ = data.completeScan(rootAlarmID: first)

        XCTAssertEqual(data.pendingScanRootIDs, [second])
        XCTAssertEqual(data.pendingScanRootID, second)
    }

    func testLegacyPendingScanMigratesToQueue() throws {
        let rootID = UUID()
        let bytes = try JSONSerialization.data(withJSONObject: [
            "alarms": [],
            "sessions": [],
            "pendingScanRootID": rootID.uuidString,
        ])

        let data = try JSONDecoder().decode(PersistedData.self, from: bytes)

        XCTAssertEqual(data.pendingScanRootIDs, [rootID])
    }

    func testConcurrentStoreUpdatesDoNotLoseAlarms() throws {
        let suite = "BudilaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BudilaStore(defaults: defaults)

        DispatchQueue.concurrentPerform(iterations: 20) { minute in
            store.update { $0.upsert(AlarmDefinition(hour: 7, minute: minute)) }
        }

        XCTAssertEqual(store.load().alarms.count, 20)
    }

    func testScannerRetriesAfterRejectedPayload() {
        var payloads: [String] = []
        let coordinator = QRScannerView.Coordinator(
            onScan: {
                payloads.append($0)
                return $0 == "expected"
            },
            onUnavailable: {}
        )

        coordinator.handle("wrong")
        coordinator.handle("wrong")
        coordinator.resetRejectedPayload()
        coordinator.handle("expected")
        coordinator.handle("ignored")

        XCTAssertEqual(payloads, ["wrong", "expected"])
        XCTAssertTrue(coordinator.completed)
    }
}
