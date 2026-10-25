import SwiftUI

struct MiniProgressBar: View {
    static let width: CGFloat = 46

    let percent: Int
    var tint: Color = .secondary

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(max(0, min(100, percent))) / 100)
            }
        }
        .frame(width: Self.width, height: 5)
    }
}
