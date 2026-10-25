import Foundation

@MainActor
enum Formatting {
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let weekdayClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, h:mm a"
        return f
    }()

    static func clockString(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func weekdayClockString(_ date: Date) -> String {
        weekdayClockFormatter.string(from: date)
    }

    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if days > 0 || hours > 0 { parts.append("\(hours)h") }
        parts.append("\(minutes)m")
        return parts.joined(separator: " ")
    }

    /// Compact "1h 15m, 5:27 PM" — countdown plus clock time, used for the
    /// near-term (5h) reset.
    static func countdownClockLabel(for date: Date, from now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        // Resets a day or more away read as "20d 6h, 10:46 AM": days and hours
        // left, then the hour it lands on.
        if seconds >= 24 * 3600 {
            let totalHours = Int(seconds / 3600)
            return "\(totalHours / 24)d \(totalHours % 24)h, \(clockString(date))"
        }
        return "\(countdown(to: date, from: now)), \(clockString(date))"
    }
}
