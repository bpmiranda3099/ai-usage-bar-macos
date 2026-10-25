import Foundation

/// Reads Claude's own usage numbers straight from `claude -p "/usage"` instead
/// of relying on agy's proxied "Claude and GPT models" figures, which lag
/// badly behind (observed stuck at 100% while Claude Code itself reported far
/// less). Output looks like:
///   Current session: 22% used · resets Sep 20 at 5:20pm (Asia/Manila)
///   Current week (all models): 58% used · resets Sep 20 at 4pm (Asia/Manila)
///   Current week (Fable): 0% used · resets Sep 20 at 4pm (Asia/Manila)
/// The per-model "Current week (<name>)" lines only appear on plans that
/// include them (e.g. Max, Team Premium), so they are optional.
enum ClaudeCodeUsageFetcher {
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

    private static let lineRegex = try! NSRegularExpression(
        pattern: #"(\d{1,3})%\s+used\s*(?:\([^)]*\))?\s*·\s*resets\s+([A-Za-z]{3}\s+\d{1,2})\s+at\s+(\d{1,2}(?::\d{2})?\s*[ap]m)\s*\(([^)]+)\)"#,
        options: [.caseInsensitive]
    )

    static func fetch() -> Result? {
        guard let output = runClaude() else { return nil }
        return parseUsage(output)
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
            return ExtraWeekly(name: name, percent: 100 - parsed.usedPercent, reset: parsed.reset)
        }

        return Result(
            fiveHourPercent: 100 - session.usedPercent,
            fiveHourReset: session.reset,
            weeklyPercent: 100 - week.usedPercent,
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
        let range = NSRange(line.startIndex..., in: line)
        guard let match = lineRegex.firstMatch(in: line, options: [], range: range) else { return nil }

        func group(_ index: Int) -> String? {
            guard let r = Range(match.range(at: index), in: line) else { return nil }
            return String(line[r])
        }

        guard let percentStr = group(1), let percent = Int(percentStr),
              let monthDay = group(2), let timeStr = group(3), let tzName = group(4) else {
            return nil
        }

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

    /// Model aliases Claude Code accepts, read from `claude -p "/model"`, e.g.
    ///   Available: sonnet, opus, haiku, fable, best, sonnet[1m], opusplan, default, or a full model ID.
    /// Context-window variants ("[1m]") and mode selectors that aren't models
    /// are dropped; the rest is capitalized for display. Local command, no model call.
    static func fetchModels() -> [String] {
        guard let output = runClaude(arguments: ["-p", "/model"]) else { return [] }
        return parseModels(output)
    }

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

    private static func runClaude(arguments: [String] = ["-p", "/usage"]) -> String? {
        let candidatePaths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
        ]
        guard let claudePath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        return SubprocessRunner.run(executablePath: claudePath, arguments: arguments)
    }
}
