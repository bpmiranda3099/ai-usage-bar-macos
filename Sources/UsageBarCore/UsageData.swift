import Foundation
import SwiftUI

struct UsageEntry: Identifiable {
    let id: String
    let displayName: String
    let tintName: String
    let fiveHourPercent: Int?
    let fiveHourReset: Date?
    let weeklyPercent: Int?
    let weeklyReset: Date?
    /// Models covered by this usage group (shown as a tooltip); empty when unknown.
    var models: [String] = []
    /// Short label for the single bar of a weekly-slot row ("wk" by default).
    var weeklyLabel = "wk"
    /// When non-empty, shown in place of the bars (e.g. local request counts).
    /// Two or more items line up under the bar columns; a single item is a plain line.
    var details: [String] = []
    /// Set for rolling per-minute meters (OpenCode provider id and requests allowed per minute).
    /// Show the single-bar reset as a countdown (daily and per-minute windows) rather than a weekday.
    var weeklyResetIsCountdown = false
    var rateProviderID: String?
    var rateLimitPerMinute: Int?

    /// Copy with a recomputed single-bar percentage and reset (used by the live per-minute refresh).
    func withWeekly(percent: Int?, reset: Date?) -> UsageEntry {
        var copy = UsageEntry(
            id: id, displayName: displayName, tintName: tintName,
            fiveHourPercent: fiveHourPercent, fiveHourReset: fiveHourReset,
            weeklyPercent: percent, weeklyReset: reset,
            models: models, weeklyLabel: weeklyLabel, details: details
        )
        copy.weeklyResetIsCountdown = weeklyResetIsCountdown
        copy.rateProviderID = rateProviderID
        copy.rateLimitPerMinute = rateLimitPerMinute
        return copy
    }

    /// Percent of a per-minute allowance left after `used` requests in the last minute.
    static func percentLeft(used: Int, limit: Int) -> Int {
        Percent.remaining(used: Double(used), limit: Double(limit))
    }

    /// Header-only entry for the OpenCode accordion (title and tint, no stats).
    static var openCodeHeader: UsageEntry {
        UsageEntry(
            id: "opencode",
            displayName: "OpenCode",
            tintName: "opencode",
            fiveHourPercent: nil,
            fiveHourReset: nil,
            weeklyPercent: nil,
            weeklyReset: nil
        )
    }

    var soonestReset: Date? {
        [fiveHourReset, weeklyReset].compactMap { $0 }.min()
    }

    var tintColor: Color {
        switch tintName {
        case "claude": return Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
        case "antigravity": return Color(red: 0.157, green: 0.471, blue: 0.941) // #2878F0
        case "opencode": return .black
        default: return .gray
        }
    }
}

enum UsageFetcher {
    private static let modelAliases: [String: (name: String, tint: String)] = [
        "Gemini Models": ("Antigravity", "antigravity"),
        "Claude and GPT models": ("Claude", "claude"),
    ]

    /// Fetches agy's figures and Claude Code's own figures concurrently
    /// (two independent subprocess calls with no data dependency between
    /// them) rather than one after another — halves wall-clock time on
    /// first launch. Bounded to exactly these two lookups, not unbounded
    /// fan-out, so it stays cheap on CPU/RAM even under load.
    static func fetch() async -> [UsageEntry] {
        async let agyOutputTask = Task.detached(priority: .userInitiated) { Tool.agy.run(["--prompt", "/usage"]) }.value
        async let modelsTask = Task.detached(priority: .userInitiated) { Tool.agy.run(["models"]) }.value
        async let openCodeTask = Task.detached(priority: .userInitiated) { OpenCodeUsageFetcher.fetch() }.value
        async let claudeCodeTask = Task.detached(priority: .userInitiated) { ClaudeCodeUsageFetcher.fetch() }.value

        async let claudeModelsTask = Task.detached(priority: .userInitiated) { ClaudeCodeUsageFetcher.fetchModels() }.value

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let output = await agyOutputTask
        let modelNames = parseModelNames(await modelsTask)
        let claudeCodeUsage = await claudeCodeTask
        let claudeModels = await claudeModelsTask
        let openCodeEntries = makeOpenCodeEntries(await openCodeTask)
        guard let output else { return openCodeEntries }

        struct Partial {
            var fiveHourPercent: Int?
            var fiveHourReset: Date?
            var weeklyPercent: Int?
            var weeklyReset: Date?
        }

        var partials: [String: Partial] = [:]
        var order: [String] = []

        for line in output.split(separator: "\n") {
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count >= 4 else { continue }
            let modelKey = cols[0]
            let limitKind = cols[1]
            let percentStr = cols[2].replacingOccurrences(of: "%", with: "")
            guard let percent = Int(percentStr), let resetDate = isoFormatter.date(from: cols[3]) else { continue }

            if partials[modelKey] == nil {
                partials[modelKey] = Partial()
                order.append(modelKey)
            }

            if limitKind.contains("Five Hour") {
                partials[modelKey]?.fiveHourPercent = percent
                partials[modelKey]?.fiveHourReset = resetDate
            } else if limitKind.contains("Weekly") {
                partials[modelKey]?.weeklyPercent = percent
                partials[modelKey]?.weeklyReset = resetDate
            }
        }

        let modelsByGroup = groupModels(modelNames, groupKeys: order)

        // agy's proxied Claude figures lag badly behind (observed stuck at
        // 100% for hours) — Claude Code itself is the source of truth for
        // its own usage, so it's shown as its own row, in addition to (not
        // replacing) agy's raw figures.
        let agyAndClaudeEntries = order.flatMap { key -> [UsageEntry] in
            // Models agy adds later show up automatically; unknown Gemini
            // models share Antigravity's tint, anything else falls back to gray.
            let alias = modelAliases[key] ?? (name: key, tint: key.hasPrefix("Gemini") ? "antigravity" : "generic")

            guard let p = partials[key] else { return [] }
            let fp = p.fiveHourPercent, fr = p.fiveHourReset
            let wp = p.weeklyPercent, wr = p.weeklyReset
            // A model may report only one of the two limits (e.g. weekly only).
            guard (fp != nil && fr != nil) || (wp != nil && wr != nil) else { return [] }

            let agyEntry = UsageEntry(
                id: key,
                displayName: key == "Claude and GPT models" ? "\(alias.name) (agy)" : alias.name,
                tintName: alias.tint,
                fiveHourPercent: fp,
                fiveHourReset: fr,
                weeklyPercent: wp,
                weeklyReset: wr,
                models: modelsByGroup[key] ?? []
            )

            if key == "Claude and GPT models", let claudeCodeUsage {
                let claudeCodeEntry = UsageEntry(
                    id: "\(key)-claude-code",
                    displayName: alias.name,
                    tintName: alias.tint,
                    fiveHourPercent: claudeCodeUsage.fiveHourPercent,
                    fiveHourReset: claudeCodeUsage.fiveHourReset,
                    weeklyPercent: claudeCodeUsage.weeklyPercent,
                    weeklyReset: claudeCodeUsage.weeklyReset,
                    models: claudeModels
                )
                let extraEntries = claudeCodeUsage.extraWeekly.map { extra in
                    UsageEntry(
                        id: "\(claudeCodeEntry.id)-\(extra.name)",
                        displayName: extra.name,
                        tintName: alias.tint,
                        fiveHourPercent: nil,
                        fiveHourReset: nil,
                        weeklyPercent: extra.percent,
                        weeklyReset: extra.reset,
                        models: claudeModels.filter { $0.caseInsensitiveCompare(extra.name) == .orderedSame }
                    )
                }
                return [claudeCodeEntry] + extraEntries + [agyEntry]
            }

            return [agyEntry]
        }
        return agyAndClaudeEntries + openCodeEntries
    }

    private static let maxTooltipModels = 15

    private static let lastUsedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static func makeOpenCodeEntries(_ providers: [OpenCodeUsageFetcher.ProviderUsage]) -> [UsageEntry] {
        func tooltip(_ provider: OpenCodeUsageFetcher.ProviderUsage) -> [String] {
            let names = provider.modelLabels.count > maxTooltipModels
                ? Array(provider.modelLabels.prefix(maxTooltipModels)) + ["+\(provider.modelLabels.count - maxTooltipModels) more"]
                : provider.modelLabels
            var header: [String] = []
            if let note = provider.quota?.note { header.append(note) }
            return header + names
        }

        var entries: [UsageEntry] = []
        var withoutMeter: [OpenCodeUsageFetcher.ProviderUsage] = []

        for provider in providers {
            // A real percentage becomes a bar.
            if let quota = provider.quota, let percent = quota.percentLeft {
                var entry = UsageEntry(
                    id: "opencode-\(provider.id)",
                    displayName: provider.name,
                    tintName: "opencode",
                    fiveHourPercent: nil,
                    fiveHourReset: nil,
                    weeklyPercent: percent,
                    weeklyReset: quota.resetAt,
                    models: tooltip(provider),
                    weeklyLabel: windowLabel(quota.label)
                )
                entry.weeklyResetIsCountdown = true
                entries.append(entry)
            } else if let limit = OpenCodeUsageFetcher.perMinuteLimits[provider.id] {
                var entry = UsageEntry(
                    id: "opencode-\(provider.id)",
                    displayName: provider.name,
                    tintName: "opencode",
                    fiveHourPercent: nil,
                    fiveHourReset: nil,
                    weeklyPercent: UsageEntry.percentLeft(used: provider.requestsLastMinute, limit: limit),
                    weeklyReset: provider.rateResetAt,
                    models: ["\(limit) requests per clock minute, counted from OpenCode on this Mac (not a provider-reported limit)"] + tooltip(provider),
                    weeklyLabel: "1m"
                )
                entry.weeklyResetIsCountdown = true
                entry.rateProviderID = provider.id
                entry.rateLimitPerMinute = limit
                entries.append(entry)
            } else {
                withoutMeter.append(provider)
            }
        }

        // Everything that has no meter shares one row; each provider's model list
        // (and any balance or history) stays available in the tooltip.
        if !withoutMeter.isEmpty {
            var lines: [String] = []
            for provider in withoutMeter {
                lines.append("\(provider.name): \(summary(of: provider))")
                lines += tooltip(provider).map { "  \($0)" }
            }
            entries.append(UsageEntry(
                id: "opencode-other",
                displayName: "Other providers",
                tintName: "opencode",
                fiveHourPercent: nil,
                fiveHourReset: nil,
                weeklyPercent: nil,
                weeklyReset: nil,
                models: lines,
                details: [withoutMeter.map(\.name).joined(separator: ", ")]
            ))
        }
        return entries
    }

    /// One-line status for a provider without a meter, used in the tooltip.
    private static func summary(of provider: OpenCodeUsageFetcher.ProviderUsage) -> String {
        if provider.requestsWeek > 0 { return "\(provider.requestsToday) today, \(provider.requestsWeek) in 7d" }
        if provider.totalRequests > 0, let lastUsed = provider.lastUsed {
            return "\(provider.totalRequests) total, last \(lastUsedFormatter.string(from: lastUsed))"
        }
        return "never used"
    }

    /// Abbreviates a quota window name ("Monthly") to fit the narrow label column.
    private static func windowLabel(_ name: String?) -> String {
        if let name, name.count <= 3 { return name }
        let lowered = name?.lowercased() ?? ""
        if lowered.contains("month") { return "mo" }
        if lowered.contains("week") { return "wk" }
        if lowered.contains("day") || lowered.contains("daily") { return "1d" }
        if lowered.contains("hour") || lowered.contains("5h") { return "5h" }
        return "–"
    }

    /// `agy models` prints "<id>\t<Display Name (Effort)>" per line (plus a
    /// status line). Returns distinct display names with the effort suffix removed.
    static func parseModelNames(_ output: String?) -> [String] {
        guard let output else { return [] }
        var names: [String] = []
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count >= 2 else { continue }
            var name = cols[1].trimmingCharacters(in: .whitespaces)
            if name.hasSuffix(")"), let open = name.lastIndex(of: "(") {
                name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
            }
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Assigns each model to a usage group without a fixed table: the group
    /// whose key is the longest prefix of the model name wins (e.g. "Gemini 4
    /// Argon"); otherwise the first group whose key mentions the model's
    /// family word (e.g. "Claude", "GPT", "Gemini").
    static func groupModels(_ names: [String], groupKeys: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for name in names {
            let lowered = name.lowercased()
            let prefixMatch = groupKeys
                .filter { lowered.hasPrefix($0.lowercased()) }
                .max { $0.count < $1.count }
            let family = lowered.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? lowered
            let key = prefixMatch ?? groupKeys.first { $0.lowercased().contains(family) }
            if let key { result[key, default: []].append(name) }
        }
        return result
    }
}
