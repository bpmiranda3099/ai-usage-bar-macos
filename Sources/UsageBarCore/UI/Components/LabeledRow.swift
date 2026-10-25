import SwiftUI

/// A row's label (hover for its tooltip), then either its meters with the reset line
/// beneath, or a single scrolling text line.
struct LabeledRow: View {
    let row: UsageRow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(verbatim: row.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Layout.rowLabelWidth, alignment: .leading)
                    .help(row.tooltip.joined(separator: "\n"))
                content
            }
            if case .meters(let short, let long) = row.content, ResetLine.hasReset(short: short, long: long) {
                ResetLine(short: short, long: long, now: now)
                    .padding(.leading, Layout.rowLabelWidth)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch row.content {
        case .meters(let short, let long):
            MeterColumns(short: short, long: long, tint: row.tint)
        case .text(let text):
            MarqueeText(text: text, width: 2 * MeterColumns.columnWidth + MeterColumns.columnSpacing)
        }
    }
}
