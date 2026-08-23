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
            pendingScanRootID: rootID
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
            pendingScanRootID: pendingID
        )

        _ = data.completeScan(rootAlarmID: completedID)

        XCTAssertEqual(data.pendingScanRootID, pendingID)
    }

    func testRemovingSessionReturnsEveryAlarmIDAndClearsState() {
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
            pendingScanRootID: rootID
        )

        let alarmIDs = data.removeSession(for: rootID)

        XCTAssertEqual(alarmIDs, Set([rootID, activeID, guardID]))
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertNil(data.pendingScanRootID)
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
