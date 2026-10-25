import Foundation

/// Brand identity of a provider; decides meter color and header glyph.
enum Tint: String, Sendable {
    case claude, antigravity, opencode

    /// Name of the glyph PNG in Resources (without extension).
    var glyphResource: String { rawValue + "-glyph" }
}
