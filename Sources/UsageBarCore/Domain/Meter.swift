import Foundation

/// One bar: a short window label ("5h", "wk", "1d"), the percent still available,
/// and when the window resets.
struct Meter: Equatable, Sendable {
    var label: String
    var percentLeft: Int
    var reset: Reset?
}

enum Reset: Equatable, Sendable {
    /// Near-term reset, shown as a countdown plus clock time ("2h 15m, 5:27 PM").
    case countdown(Date)
    /// Landing day and time ("Thu, 10:00 AM").
    case calendar(Date)
}
