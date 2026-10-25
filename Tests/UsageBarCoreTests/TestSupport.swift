import Foundation

/// Parses an ISO-8601 UTC timestamp for use in tests.
func iso(_ text: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: text) else {
        fatalError("bad test date: \(text)")
    }
    return date
}
