import SwiftUI

/// "5h [bar] 100%   wk [bar] 66%": up to two meters in fixed columns. A row that only
/// has the long meter leaves the first column empty so its bar lines up with the others.
struct MeterColumns: View {
    let short: Meter?
    let long: Meter?
    let tint: Tint

    // Shared with ResetLine so the reset row lines up under the bars.
    static let labelWidth: CGFloat = 16
    static let barLabelSpacing: CGFloat = 6
    static let percentWidth: CGFloat = 34
    static let columnSpacing: CGFloat = 18
    static let columnWidth: CGFloat = labelWidth + barLabelSpacing + MiniProgressBar.width + barLabelSpacing + percentWidth

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            if let short {
                column(short)
            } else if long != nil {
                Color.clear.frame(width: Self.columnWidth, height: 1)
            }
            if let long {
                column(long)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func column(_ meter: Meter) -> some View {
        HStack(spacing: Self.barLabelSpacing) {
            Text(verbatim: meter.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.labelWidth, alignment: .leading)
            MiniProgressBar(percent: meter.percentLeft, tint: tint.color)
            Text(verbatim: "\(meter.percentLeft)%")
                .font(.system(size: 11, weight: .medium))
                .frame(width: Self.percentWidth, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
