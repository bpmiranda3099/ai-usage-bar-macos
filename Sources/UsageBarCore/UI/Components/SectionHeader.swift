import SwiftUI

/// A section's icon, title and expand/collapse caret. The whole header is the button.
struct SectionHeader: View {
    let title: String
    let tint: Tint
    @Binding var isExpanded: Bool

    // Measured from a native macOS menu-extra row (e.g. Battery's "Low
    // Power" icon): 52px circle at 2x scale = 26pt, matched against the
    // adjacent row-title text pixel height to calibrate the scale factor.
    private static let iconDiameter: CGFloat = 26
    private static let glyphSize: CGFloat = 14

    private var glyphImage: NSImage? {
        Bundle.module.url(forResource: tint.glyphResource, withExtension: "png", subdirectory: "Resources")
            .flatMap { NSImage(contentsOf: $0) }
    }

    var body: some View {
        Button {
            withAnimation(Layout.toggleAnimation) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                icon
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            Circle().fill(tint.color).frame(width: Self.iconDiameter, height: Self.iconDiameter)
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
