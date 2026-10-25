import Foundation

/// Parses Claude Code's own usage numbers from `claude -p "/usage"` instead
/// of relying on agy's proxied "Claude and GPT models" figures, which lag
/// badly behind (observed stuck at 100% while Claude Code itself reported far
/// less). Output looks like:
///   Current session: 22% used · resets Sep 20 at 5:20pm (Asia/Manila)
///   Current week (all models): 58% used · resets Sep 20 at 4pm (Asia/Manila)
///   Current week (Fable): 0% used · resets Sep 20 at 4pm (Asia/Manila)
/// The per-model "Current week (<name>)" lines only appear on plans that
/// include them (e.g. Max, Team Premium), so they are optional.
enum ClaudeUsageParser {
    struct Result {
        let fiveHourPercent: Int
        let fiveHourReset: Date
        let weeklyPercent: Int
        let weeklyReset: Date
        let extraWeekly: [ExtraWeekly]
    }

    struct ExtraWeekly {
        let name: String
        let percent: Int
        let reset: Date
    }

    /// `now` decides which year the year-less dates in the output belong to.
    static func parseUsage(_ output: String, now: Date = Date()) -> Result? {
        let lines = output.split(separator: "\n").map(String.init)

        guard let sessionLine = lines.first(where: { $0.contains("Current session") }),
              let weekLine = lines.first(where: { $0.contains("Current week") }),
              let session = parse(sessionLine, now: now),
              let week = parse(weekLine, now: now) else {
            return nil
        }

        let extras = lines.compactMap { line -> ExtraWeekly? in
            guard let name = extraWeeklyName(in: line), let parsed = parse(line, now: now) else { return nil }
            return ExtraWeekly(name: name, percent: Percent.clamped(100 - parsed.usedPercent), reset: parsed.reset)
        }

        return Result(
            fiveHourPercent: Percent.clamped(100 - session.usedPercent),
            fiveHourReset: session.reset,
            weeklyPercent: Percent.clamped(100 - week.usedPercent),
            weeklyReset: week.reset,
            extraWeekly: extras
        )
    }

    /// "Current week (Fable): ..." -> "Fable"; nil for the all-models line and non-matching lines.
    private static func extraWeeklyName(in line: String) -> String? {
        let prefix = "Current week ("
        guard line.hasPrefix(prefix), let close = line.firstIndex(of: ")") else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<close])
        return name.caseInsensitiveCompare("all models") == .orderedSame ? nil : name
    }

    private static func parse(_ line: String, now: Date) -> (usedPercent: Int, reset: Date)? {
        // The pattern is a compile-time checked literal, so there is no runtime regex construction to fail.
        guard let match = line.firstMatch(of: /(\d{1,3})%\s+used\s*(?:\([^)]*\)\s*)?·\s*resets\s+([A-Za-z]{3}\s+\d{1,2})\s+at\s+(\d{1,2}(?::\d{2})?\s*[ap]m)\s*\(([^)]+)\)/.ignoresCase()),
              let percent = Int(match.1) else { return nil }
        let monthDay = String(match.2), timeStr = String(match.3), tzName = String(match.4)

        let normalizedTime = timeStr.replacingOccurrences(of: " ", with: "")
        let hasMinutes = normalizedTime.contains(":")
        let year = Calendar.current.component(.year, from: now)
        let dateString = "\(monthDay) \(year) \(normalizedTime)"
        let format = hasMinutes ? "MMM d yyyy h:mma" : "MMM d yyyy ha"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(identifier: tzName) ?? .current

        guard var date = formatter.date(from: dateString) else { return nil }

        // No year in the source text; if the parsed date already passed,
        // it must refer to the next occurrence (roll forward a day for the
        // 5h session window, a week for the weekly window).
        if date <= now {
            let isWeekly = line.contains("week")
            date = date.addingTimeInterval(isWeekly ? 7 * 86400 : 86400)
        }

        return (percent, date)
    }

    /// Model aliases from `claude -p "/model"`, e.g.
    ///   Available: sonnet, opus, haiku, fable, best, sonnet[1m], opusplan, default, or a full model ID.
    /// Context-window variants ("[1m]") and mode selectors that aren't models are dropped;
    /// the rest is capitalized for display.
    static func parseModels(_ output: String) -> [String] {
        guard let range = output.range(of: "Available:") else { return [] }
        let selectorsThatAreNotModels: Set<String> = ["best", "default", "opusplan"]
        let list = output[range.upperBound...].split(separator: "\n").first.map(String.init) ?? ""
        var names: [String] = []
        for token in list.split(separator: ",") {
            let alias = token.trimmingCharacters(in: .whitespaces)
            guard !alias.isEmpty, !alias.contains("["), !alias.contains(" "),
                  !selectorsThatAreNotModels.contains(alias.lowercased()) else { continue }
            let name = alias.prefix(1).uppercased() + alias.dropFirst()
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}
