import SwiftUI

/// Single-line text in a fixed width. When the text is wider than the width it
/// glides to the end and back so the clipped part can be read; otherwise it is static.
struct MarqueeText: View {
    let text: String
    let width: CGFloat

    private static let pointsPerSecond: Double = 28
    private static let pause: Double = 1.2

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - width) }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            .offset(x: offset)
            .frame(width: width, alignment: .leading)
            .clipped()
            .onAppear(perform: restart)
            .onChange(of: textWidth) { restart() }
            .onChange(of: text) { restart() }
            .onDisappear { offset = 0 }
    }

    private func restart() {
        offset = 0
        guard overflow > 0 else { return }
        let duration = Double(overflow) / Self.pointsPerSecond
        // Re-evaluated on the next runloop turn so the reset to 0 lands first.
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration).delay(Self.pause).repeatForever(autoreverses: true)) {
                offset = -overflow
            }
        }
    }
}
