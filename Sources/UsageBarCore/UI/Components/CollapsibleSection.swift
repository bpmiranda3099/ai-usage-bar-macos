import SwiftUI

private struct SectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// Clips its content to an animatable height so collapsing slides the content
/// up under its header (and expanding slides it back down) instead of fading
/// in place. The content stays in the tree so its natural height is always known.
struct CollapsibleSection<Content: View>: View {
    let isExpanded: Bool
    /// Reports the content's natural (fully expanded) height whenever it changes.
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    @State private var naturalHeight: CGFloat?

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SectionHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(SectionHeightKey.self) { height in
                naturalHeight = height
                if let height { onHeightChange(height) }
            }
            .frame(height: isExpanded ? naturalHeight : 0, alignment: .top)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
    }
}
