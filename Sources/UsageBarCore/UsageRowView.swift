import SwiftUI

struct UsageRowView: View {
    let entry: UsageEntry
    let now: Date
    var showsStats = true
    /// When set, the header becomes a button that toggles this accordion state.
    var isExpanded: Binding<Bool>?

    private var glyphImage: NSImage? {
        guard let url = Bundle.module.url(forResource: entry.tintName + "-glyph", withExtension: "png", subdirectory: "Resources") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if showsStats {
                UsageStatColumns(entry: entry)
                UsageResetLines(entry: entry, now: now)
            }
        }
        // Header-only rows must stretch to the panel width so the caret hugs the right edge.
        .fixedSize(horizontal: showsStats, vertical: false)
    }

    @ViewBuilder
    private var header: some View {
        let title = HStack(spacing: 10) {
            iconView

            Text(entry.displayName)
                .font(.system(size: 13, weight: .semibold))

            if let isExpanded {
                Spacer(minLength: 0)
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        if let isExpanded {
            Button {
                withAnimation(ContentView.toggleAnimation) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                title.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            title
        }
    }

    // Measured from a native macOS menu-extra row (e.g. Battery's "Low
    // Power" icon): 52px circle at 2x scale = 26pt, matched against the
    // adjacent row-title text pixel height to calibrate the scale factor.
    private static let iconDiameter: CGFloat = 26
    private static let glyphSize: CGFloat = 14

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            Circle().fill(entry.tintColor).frame(width: Self.iconDiameter, height: Self.iconDiameter)
            if let glyphImage {
                Image(nsImage: glyphImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.glyphSize, height: Self.glyphSize)
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "sparkle")
                    .symbolVariant(.fill)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
