import Foundation

/// One collapsible group in the panel (a provider's header plus its rows).
struct UsageSection: Identifiable, Sendable {
    /// Stable id; also the key under which the expanded state is saved.
    let id: String
    let title: String
    let tint: Tint
    var rows: [UsageRow]
}
