import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct BudilaWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudilaAlarmLiveActivity()
    }
}

struct BudilaAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<BudilaAlarmMetadata>.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.metadata?.label ?? "Alarm")
                        .font(.headline)
                    status(context)
                        .font(.title2.monospacedDigit())
                }
                Spacer()
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
                    .accessibilityLabel("Scan QR code")
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.metadata?.label ?? "Alarm", systemImage: "alarm.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    status(context).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label("Scan the enrolled QR code", systemImage: "qrcode.viewfinder")
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            } compactTrailing: {
                status(context).monospacedDigit()
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func status(_ context: ActivityViewContext<AlarmAttributes<BudilaAlarmMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
        case .paused:
            Text("Paused")
        case .alert:
            Text("Scan to finish")
        @unknown default:
            Text("Alarm")
        }
    }
}
