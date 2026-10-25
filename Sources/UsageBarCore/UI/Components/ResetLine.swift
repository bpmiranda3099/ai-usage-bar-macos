import SwiftUI

/// One compact line for both resets, icon-led: a clock for countdowns, a calendar for
/// a landing day/time. Aligned under the meter columns.
struct ResetLine: View {
    let short: Meter?
    let long: Meter?
    let now: Date

    var body: some View {
        HStack(spacing: MeterColumns.columnSpacing) {
            if let reset = short?.reset {
                label(for: reset)
                    .frame(minWidth: MeterColumns.columnWidth, alignment: .leading)
            } else if long?.reset != nil {
                Color.clear.frame(width: MeterColumns.columnWidth, height: 1)
            }
            if let reset = long?.reset {
                label(for: reset)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func label(for reset: Reset) -> some View {
        HStack(spacing: 4) {
            switch reset {
            case .countdown(let date):
                Image(systemName: "clock")
                Text(verbatim: Formatting.countdownClockLabel(for: date, from: now))
            case .calendar(let date):
                Image(systemName: "calendar")
                Text(verbatim: Formatting.weekdayClockString(date))
            }
        }
    }

    /// Whether there is anything to show for these meters.
    static func hasReset(short: Meter?, long: Meter?) -> Bool {
        short?.reset != nil || long?.reset != nil
    }
}
