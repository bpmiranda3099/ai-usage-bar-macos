import Foundation

/// Claude Code usage from its own CLI, which is the source of truth for its limits.
struct ClaudeCodeProvider: UsageProvider {
    func sections() async -> [UsageSection] {
        async let usage = inBackground { Tool.claude.run(["-p", "/usage"]).flatMap { ClaudeUsageParser.parseUsage($0) } }
        async let models = inBackground { Tool.claude.run(["-p", "/model"]).map(ClaudeUsageParser.parseModels) ?? [] }
        return Self.sections(usage: await usage, models: await models)
    }

    static func sections(usage: ClaudeUsageParser.Result?, models: [String]) -> [UsageSection] {
        guard let usage else { return [] }

        let main = UsageRow(
            id: "claude-models",
            label: "Claude Models",
            tooltip: models,
            tint: .claude,
            content: .meters(
                short: Meter(label: "5h", percentLeft: usage.fiveHourPercent, reset: .countdown(usage.fiveHourReset)),
                long: Meter(label: "wk", percentLeft: usage.weeklyPercent, reset: .calendar(usage.weeklyReset))
            )
        )
        // Per-model weekly limits (e.g. Fable) only exist on some plans.
        let extras = usage.extraWeekly.map { extra in
            UsageRow(
                id: "claude-\(extra.name)",
                label: "Claude \(extra.name)",
                tooltip: models.filter { $0.caseInsensitiveCompare(extra.name) == .orderedSame },
                tint: .claude,
                content: .meters(short: nil, long: Meter(label: "wk", percentLeft: extra.percent, reset: .calendar(extra.reset)))
            )
        }
        return [UsageSection(id: "claude", title: "Claude", tint: .claude, rows: [main] + extras)]
    }
}
