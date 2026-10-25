import Foundation

/// One labeled line inside a section.
struct UsageRow: Identifiable, Sendable {
    enum Content: Equatable, Sendable {
        /// Up to two bars in fixed columns: a short window and a long window.
        case meters(short: Meter?, long: Meter?)
        /// A plain line (scrolls when it does not fit).
        case text(String)
    }

    let id: String
    let label: String
    var tooltip: [String] = []
    let tint: Tint
    var content: Content
    /// Recomputes the long meter from local data while the panel is open (per-minute meters).
    var liveMeter: (@Sendable () -> Meter?)?

    /// Copy with the long meter replaced; no-op for text rows.
    func replacingLongMeter(_ meter: Meter) -> UsageRow {
        guard case .meters(let short, _) = content else { return self }
        var copy = self
        copy.content = .meters(short: short, long: meter)
        return copy
    }
}
