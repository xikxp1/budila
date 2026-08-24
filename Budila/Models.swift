import CryptoKit
import Foundation

enum BudilaWeekday: Int, Codable, CaseIterable, Hashable, Identifiable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var alarmKitValue: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }
}

struct AlarmDefinition: Codable, Equatable, Identifiable {
    var id = UUID()
    var hour = 7
    var minute = 0
    var weekdays = Set(BudilaWeekday.allCases)
    var label = "Alarm"
    var enabled = true

    var displayLabel: String {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Alarm" : value
    }

    var time: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    func nextGuardDate(after now: Date = .now, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var alarmDate = calendar.date(from: components) else { return now.addingTimeInterval(60) }
        if alarmDate > now {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: alarmDate) else {
                return now.addingTimeInterval(60)
            }
            alarmDate = previousDay
        }

        for snooze in 1...SnoozeLimit.maximum {
            let date = alarmDate.addingTimeInterval(SnoozeLimit.duration * Double(snooze))
            if date > now { return date }
        }
        return now.addingTimeInterval(60)
    }

    var daysDescription: String {
        if weekdays.count == BudilaWeekday.allCases.count { return "Every day" }
        return BudilaWeekday.allCases.filter(weekdays.contains).map(\.shortName).joined(separator: " ")
    }
}

enum AlarmSessionKind: String, Codable {
    case snoozed
    case guardAlarm
}

struct AlarmSession: Codable, Equatable, Identifiable {
    var rootAlarmID: UUID
    var activeAlarmID: UUID
    var guardAlarmID: UUID?
    var snoozesUsed: Int
    var kind: AlarmSessionKind

    var id: UUID { rootAlarmID }
}

struct PersistedData: Equatable {
    var alarms: [AlarmDefinition] = []
    var qrDigest: String?
    var sessions: [AlarmSession] = []
    var pendingScanRootIDs: [UUID] = []

    var pendingScanRootID: UUID? { pendingScanRootIDs.first }

    mutating func upsert(_ alarm: AlarmDefinition) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        alarms.sort { ($0.hour, $0.minute, $0.id.uuidString) < ($1.hour, $1.minute, $1.id.uuidString) }
    }

    mutating func upsert(_ session: AlarmSession) {
        sessions.removeAll { $0.rootAlarmID == session.rootAlarmID }
        sessions.append(session)
    }

    mutating func enqueueScan(rootAlarmID: UUID) {
        guard !pendingScanRootIDs.contains(rootAlarmID) else { return }
        pendingScanRootIDs.append(rootAlarmID)
    }

    mutating func completeScan(rootAlarmID: UUID) -> AlarmSession? {
        pendingScanRootIDs.removeAll { $0 == rootAlarmID }
        guard let index = sessions.firstIndex(where: { $0.rootAlarmID == rootAlarmID }) else { return nil }
        return sessions.remove(at: index)
    }

    func alarmIDsForRemoval(rootAlarmID: UUID) -> [UUID] {
        var alarmIDs: [UUID] = []
        if let session = sessions.first(where: { $0.rootAlarmID == rootAlarmID }) {
            for id in [session.activeAlarmID, session.guardAlarmID].compactMap({ $0 })
                where id != rootAlarmID && !alarmIDs.contains(id) {
                alarmIDs.append(id)
            }
        }
        // Cancel the recurring root last so a child failure cannot silently disable it.
        alarmIDs.append(rootAlarmID)
        return alarmIDs
    }

    mutating func removeSession(for rootAlarmID: UUID) {
        sessions.removeAll { $0.rootAlarmID == rootAlarmID }
        pendingScanRootIDs.removeAll { $0 == rootAlarmID }
    }
}

extension PersistedData: Codable {
    private enum CodingKeys: String, CodingKey {
        case alarms, qrDigest, sessions, pendingScanRootIDs, pendingScanRootID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alarms = try values.decodeIfPresent([AlarmDefinition].self, forKey: .alarms) ?? []
        qrDigest = try values.decodeIfPresent(String.self, forKey: .qrDigest)
        sessions = try values.decodeIfPresent([AlarmSession].self, forKey: .sessions) ?? []
        if let ids = try values.decodeIfPresent([UUID].self, forKey: .pendingScanRootIDs) {
            pendingScanRootIDs = ids
        } else if let id = try values.decodeIfPresent(UUID.self, forKey: .pendingScanRootID) {
            pendingScanRootIDs = [id]
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(alarms, forKey: .alarms)
        try values.encodeIfPresent(qrDigest, forKey: .qrDigest)
        try values.encode(sessions, forKey: .sessions)
        try values.encode(pendingScanRootIDs, forKey: .pendingScanRootIDs)
    }
}

struct BudilaStore: @unchecked Sendable {
    static let storageKey = "budila.data.v1"
    // ponytail: process-local lock; use coordinated file storage if alarm intents move to another process.
    private static let lock = NSLock()
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedData {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return loadUnlocked()
    }

    func save(_ data: PersistedData) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        saveUnlocked(data)
    }

    @discardableResult
    func update(_ change: (inout PersistedData) throws -> Void) rethrows -> PersistedData {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var data = loadUnlocked()
        try change(&data)
        saveUnlocked(data)
        return data
    }

    private func loadUnlocked() -> PersistedData {
        guard let bytes = defaults.data(forKey: Self.storageKey),
              let data = try? JSONDecoder().decode(PersistedData.self, from: bytes) else {
            return PersistedData()
        }
        return data
    }

    private func saveUnlocked(_ data: PersistedData) {
        guard let bytes = try? JSONEncoder().encode(data) else { return }
        defaults.set(bytes, forKey: Self.storageKey)
    }
}

enum QRCodeDigest {
    static func make(_ payload: String) -> String {
        SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func matches(_ payload: String, digest: String?) -> Bool {
        guard let digest else { return false }
        return make(payload) == digest
    }
}

enum SnoozeLimit {
    static let maximum = 2
    static let duration: TimeInterval = 180

    static func allows(_ used: Int) -> Bool {
        used < maximum
    }
}
