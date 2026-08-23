import AlarmKit

struct BudilaAlarmMetadata: AlarmMetadata, Hashable {
    let rootAlarmID: String
    let label: String
}
