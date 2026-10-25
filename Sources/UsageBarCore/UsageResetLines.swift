import SwiftUI

/// One compact line for both resets, icon-led instead of repeating
/// "resets in" text: a clock for the near-term 5h countdown, a calendar for
/// the weekly landing day/time.
struct UsageResetLines: View {
    let entry: UsageEntry
    let now: Date

    var body: some View {
        HStack(spacing: UsageStatColumns.columnSpacing) {
            if let fiveHourReset = entry.fiveHourReset {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(Formatting.countdownClockLabel(for: fiveHourReset, from: now))
                }
                .frame(minWidth: UsageStatColumns.columnWidth, alignment: .leading)
            } else if entry.weeklyReset != nil {
                Color.clear.frame(width: UsageStatColumns.columnWidth, height: 1)
            }

            if let weeklyReset = entry.weeklyReset {
                HStack(spacing: 4) {
                    Image(systemName: entry.weeklyResetIsCountdown ? "clock" : "calendar")
                    Text(entry.weeklyResetIsCountdown
                         ? Formatting.countdownClockLabel(for: weeklyReset, from: now)
                         : Formatting.weekdayClockString(weeklyReset))
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }
}
