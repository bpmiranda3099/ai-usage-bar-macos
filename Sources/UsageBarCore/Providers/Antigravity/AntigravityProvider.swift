import Foundation

/// Antigravity usage from the `agy` CLI: one row per usage group it reports.
struct AntigravityProvider: UsageProvider {
    private static let geminiKey = "Gemini Models"
    private static let claudeKey = "Claude and GPT models"

    func sections() async -> [UsageSection] {
        async let usage = inBackground { Tool.agy.run(["--prompt", "/usage"]) }
        async let models = inBackground { Tool.agy.run(["models"]) }
        return Self.sections(
            groups: AgyOutputParser.parse(await usage ?? ""),
            modelNames: ModelGrouping.displayNames(from: await models)
        )
    }

    static func sections(groups: [AgyGroup], modelNames: [String]) -> [UsageSection] {
        let modelsByGroup = ModelGrouping.group(modelNames, keys: groups.map(\.key))

        // Gemini first, then Claude/GPT, then anything else agy adds, in agy's order.
        let leading = [geminiKey, claudeKey]
        let ordered = groups.enumerated().sorted { lhs, rhs in
            let l = leading.firstIndex(of: lhs.element.key) ?? leading.count
            let r = leading.firstIndex(of: rhs.element.key) ?? leading.count
            return (l, lhs.offset) < (r, rhs.offset)
        }.map(\.element)

        let rows = ordered.map { group in
            UsageRow(
                id: "antigravity-\(group.key)",
                label: group.key.replacingOccurrences(of: "models", with: "Models"),
                tooltip: modelsByGroup[group.key] ?? [],
                tint: group.key == claudeKey ? .claude : .antigravity,
                content: .meters(
                    short: group.fiveHour.map { Meter(label: "5h", percentLeft: $0.percentLeft, reset: .countdown($0.reset)) },
                    long: group.weekly.map { Meter(label: "wk", percentLeft: $0.percentLeft, reset: .calendar($0.reset)) }
                )
            )
        }
        return rows.isEmpty ? [] : [UsageSection(id: "antigravity", title: "Antigravity", tint: .antigravity, rows: rows)]
    }
}
