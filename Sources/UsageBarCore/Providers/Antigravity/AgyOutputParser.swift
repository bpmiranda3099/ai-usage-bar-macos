import Foundation

/// One usage group from `agy --prompt "/usage"`, e.g. "Gemini Models".
struct AgyGroup: Equatable {
    struct Window: Equatable {
        let percentLeft: Int
        let reset: Date
    }

    let key: String
    var fiveHour: Window?
    var weekly: Window?
}

enum AgyOutputParser {
    /// Lines look like "<group>\t<limit name>\t97%\t2026-10-31T04:58:26Z". Groups keep
    /// the order of first appearance; lines that don't parse are skipped, and groups
    /// with neither window are dropped.
    static func parse(_ output: String) -> [AgyGroup] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var groups: [AgyGroup] = []
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count >= 4,
                  let percent = Int(cols[2].replacingOccurrences(of: "%", with: "")),
                  let reset = formatter.date(from: cols[3]) else { continue }

            let window = AgyGroup.Window(percentLeft: percent, reset: reset)
            let index = groups.firstIndex { $0.key == cols[0] } ?? {
                groups.append(AgyGroup(key: cols[0]))
                return groups.count - 1
            }()

            if cols[1].contains("Five Hour") {
                groups[index].fiveHour = window
            } else if cols[1].contains("Weekly") {
                groups[index].weekly = window
            }
        }
        return groups.filter { $0.fiveHour != nil || $0.weekly != nil }
    }
}
