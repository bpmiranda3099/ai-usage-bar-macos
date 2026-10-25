import Foundation

/// OpenCode's connected providers. Providers with a quota or a per-minute cap get a
/// meter row; everything else shares one "Other providers" row (model lists live in
/// its tooltip).
struct OpenCodeProvider: UsageProvider {
    private static let maxTooltipModels = 15

    func sections() async -> [UsageSection] {
        let providers = await inBackground { OpenCodeUsageFetcher.fetch() }
        return Self.sections(from: providers)
    }

    static func sections(
        from providers: [OpenCodeUsageFetcher.ProviderUsage],
        perMinuteLimits: [String: Int] = OpenCodeUsageFetcher.perMinuteLimits
    ) -> [UsageSection] {
        var rows: [UsageRow] = []
        var withoutMeter: [OpenCodeUsageFetcher.ProviderUsage] = []

        for provider in providers {
            if let quota = provider.quota, let percent = quota.percentLeft {
                rows.append(UsageRow(
                    id: "opencode-\(provider.id)",
                    label: provider.name,
                    tooltip: tooltip(for: provider),
                    tint: .opencode,
                    content: .meters(short: nil, long: Meter(
                        label: windowLabel(quota.label),
                        percentLeft: percent,
                        reset: quota.resetAt.map(Reset.countdown)
                    ))
                ))
            } else if let limit = perMinuteLimits[provider.id] {
                let note = "\(limit) requests per clock minute, counted from OpenCode on this Mac (not a provider-reported limit)"
                var row = UsageRow(
                    id: "opencode-\(provider.id)",
                    label: provider.name,
                    tooltip: [note] + tooltip(for: provider),
                    tint: .opencode,
                    content: .meters(short: nil, long: perMinuteMeter(used: provider.requestsLastMinute, limit: limit, reset: provider.rateResetAt))
                )
                let providerID = provider.id
                row.liveMeter = {
                    OpenCodeUsageFetcher.requestsInLastMinute(providerID: providerID).map {
                        perMinuteMeter(used: $0.count, limit: limit, reset: $0.resetAt)
                    }
                }
                rows.append(row)
            } else {
                withoutMeter.append(provider)
            }
        }

        if !withoutMeter.isEmpty {
            var lines: [String] = []
            for provider in withoutMeter {
                lines.append("\(provider.name): \(summary(of: provider))")
                lines += tooltip(for: provider).map { "  \($0)" }
            }
            rows.append(UsageRow(
                id: "opencode-other",
                label: "Other providers",
                tooltip: lines,
                tint: .opencode,
                content: .text(withoutMeter.map(\.name).joined(separator: ", "))
            ))
        }
        return rows.isEmpty ? [] : [UsageSection(id: "openCode", title: "OpenCode", tint: .opencode, rows: rows)]
    }

    private static func perMinuteMeter(used: Int, limit: Int, reset: Date?) -> Meter {
        Meter(label: "1m", percentLeft: Percent.remaining(used: Double(used), limit: Double(limit)), reset: reset.map(Reset.countdown))
    }

    private static func tooltip(for provider: OpenCodeUsageFetcher.ProviderUsage) -> [String] {
        let labels = provider.modelLabels
        let names = labels.count > maxTooltipModels
            ? Array(labels.prefix(maxTooltipModels)) + ["+\(labels.count - maxTooltipModels) more"]
            : labels
        return (provider.quota?.note).map { [$0] + names } ?? names
    }

    /// One-line status for a provider without a meter, used in the tooltip.
    private static func summary(of provider: OpenCodeUsageFetcher.ProviderUsage) -> String {
        if provider.requestsWeek > 0 { return "\(provider.requestsToday) today, \(provider.requestsWeek) in 7d" }
        if provider.totalRequests > 0, let lastUsed = provider.lastUsed {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(provider.totalRequests) total, last \(formatter.string(from: lastUsed))"
        }
        return "never used"
    }

    /// Abbreviates a quota window name ("Monthly") to fit the narrow label column.
    static func windowLabel(_ name: String?) -> String {
        if let name, name.count <= 3 { return name }
        let lowered = name?.lowercased() ?? ""
        if lowered.contains("month") { return "mo" }
        if lowered.contains("week") { return "wk" }
        if lowered.contains("day") || lowered.contains("daily") { return "1d" }
        if lowered.contains("hour") || lowered.contains("5h") { return "5h" }
        return "–"
    }
}
