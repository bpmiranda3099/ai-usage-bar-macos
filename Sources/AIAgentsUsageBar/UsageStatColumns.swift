import SwiftUI

/// The bare "5h [bar] 100%   wk [bar] 66%" stat line, shared between full
/// UsageRowView cards and standalone bare rows (e.g. the raw agy Claude
/// figures shown without their own icon/title/reset header).
struct UsageStatColumns: View {
    let entry: UsageEntry

    // Shared with UsageResetLines so the reset row below lines up exactly
    // under the "5h"/"wk" columns instead of drifting based on its own text
    // width.
    static let labelWidth: CGFloat = 16
    static let barLabelSpacing: CGFloat = 6
    static let percentWidth: CGFloat = 34
    static let columnSpacing: CGFloat = 18
    static let columnWidth: CGFloat = labelWidth + barLabelSpacing + MiniProgressBar.width + barLabelSpacing + percentWidth

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            if !entry.details.isEmpty {
                ForEach(entry.details, id: \.self) { detail in
                    if entry.details.count > 1 {
                        detailText(detail).frame(width: Self.columnWidth, alignment: .leading)
                    } else {
                        // Long single lines (e.g. a provider list) scroll instead of widening the panel.
                        MarqueeText(text: detail, width: 2 * Self.columnWidth + Self.columnSpacing)
                    }
                }
            } else if let percent = entry.fiveHourPercent {
                stat(label: "5h", percent: percent)
            } else if entry.weeklyPercent != nil {
                // Weekly-only models keep their "wk" bar in the weekly column.
                Color.clear.frame(width: Self.columnWidth, height: 1)
            }
            if entry.details.isEmpty, let percent = entry.weeklyPercent {
                stat(label: entry.weeklyLabel, percent: percent)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func stat(label: String, percent: Int) -> some View {
        HStack(spacing: Self.barLabelSpacing) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.labelWidth, alignment: .leading)
            MiniProgressBar(percent: percent, tint: entry.tintColor)
            Text("\(percent)%")
                .font(.system(size: 11, weight: .medium))
                .frame(width: Self.percentWidth, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
