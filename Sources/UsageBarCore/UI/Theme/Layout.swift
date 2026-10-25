import SwiftUI

/// Measurements shared by more than one view.
enum Layout {
    static let cornerRadius: CGFloat = 20
    /// Horizontal padding between the panel edge and its content.
    static let inset: CGFloat = 16
    /// Width of the row label column; the bars start after it.
    static let rowLabelWidth: CGFloat = 144

    static let toggleDuration: TimeInterval = 0.25
    static let toggleAnimation = Animation.easeInOut(duration: toggleDuration)
}

extension View {
    func panelInset() -> some View {
        padding(.horizontal, Layout.inset)
    }
}
