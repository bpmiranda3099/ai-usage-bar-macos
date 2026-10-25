import Foundation

/// One combined meter for Google AI Studio's free tier.
///  - Limits: read live from your Google project (Service Usage API, per model,
///    per minute and per day) using `gcloud`'s access token. Nothing is hardcoded.
///  - Usage: Google only exposes usage through Cloud Monitoring, which needs billing
///    enabled, so requests are counted from OpenCode's local history instead
///    (requests made through OpenCode on this Mac only).
///  - The project id comes from ~/.config/ai-agents-usage-bar/settings.json
///    (`googleProjectId`); without it, or without a `gcloud` login, no meter is shown.
enum GoogleFreeTier {
    struct ModelLimit {
        var perMinute: Int?
        var perDay: Int?
    }

    private static let limitsCacheSeconds: TimeInterval = 6 * 3600

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var limits: [String: ModelLimit]?
        var fetchedAt: Date?
    }
    private static let cache = Cache()

    static func quota(models: Set<String>, databasePath: String?) -> OpenCodeUsageFetcher.Quota? {
        guard let databasePath, let projectID = projectID(), let limits = modelLimits(projectID: projectID) else { return nil }

        // Quota model names are short ("gemma-4-26b"); OpenCode ids are longer
        // ("gemma-4-26b-a4b-it"), so match each id to its longest quota-name prefix.
        func limit(for modelID: String) -> (name: String, limit: ModelLimit)? {
            limits.keys.filter { modelID.hasPrefix($0) }.max { $0.count < $1.count }.flatMap { key in
                limits[key].map { (key, $0) }
            }
        }

        let usedToday = requestsSincePacificMidnight(databasePath: databasePath)
        var lines: [String] = []
        var seen = Set<String>()
        var totalUsed = 0.0
        var totalLimit = 0.0

        for modelID in models.sorted() {
            guard let (name, modelLimit) = limit(for: modelID), seen.insert(name).inserted,
                  let perDay = modelLimit.perDay, perDay > 0 else { continue }

            let used = usedToday.filter { limit(for: $0.key)?.name == name }.values.reduce(0, +)
            var line = "\(name): \(used)/\(perDay) per day"
            if let perMinute = modelLimit.perMinute, perMinute > 0 { line += ", \(perMinute)/min" }
            lines.append(line)

            // The combined meter covers the models actually used today, so unused
            // models with large caps don't make the bar look emptier than it is.
            if used > 0 {
                totalUsed += Double(used)
                totalLimit += Double(perDay)
            }
        }
        guard !lines.isEmpty else { return nil }

        let percentLeft = totalLimit > 0 ? Percent.remaining(used: totalUsed, limit: totalLimit) : 100
        let header = "Google free tier, per model (limits from your project; usage counted from OpenCode on this Mac, resets midnight Pacific)"
        return OpenCodeUsageFetcher.Quota(label: "1d", percentLeft: percentLeft, note: ([header] + lines).joined(separator: "\n"), resetAt: ProviderUsageAPI.nextMidnight(in: "America/Los_Angeles"))
    }

    // MARK: Limits

    private static func projectID() -> String? {
        let path = "\(NSHomeDirectory())/.config/ai-agents-usage-bar/settings.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["googleProjectId"] as? String,
              id.range(of: #"^[a-z][a-z0-9-]{4,60}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    private static func modelLimits(projectID: String) -> [String: ModelLimit]? {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let limits = cache.limits, let fetchedAt = cache.fetchedAt, Date().timeIntervalSince(fetchedAt) < limitsCacheSeconds {
            return limits
        }

        guard let token = Tool.gcloud.run(["auth", "print-access-token"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty,
              let url = URL(string: "https://serviceusage.googleapis.com/v1beta1/projects/\(projectID)/services/generativelanguage.googleapis.com/consumerQuotaMetrics?view=FULL&pageSize=200"),
              let data = ProviderUsageAPI.get(url, bearer: token, extraHeaders: ["x-goog-user-project": projectID]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metrics = root["metrics"] as? [[String: Any]] else {
            return cache.limits   // keep the last good limits if this refresh fails
        }

        var limits: [String: ModelLimit] = [:]
        for metric in metrics {
            let name = (metric["metric"] as? String) ?? ""
            guard name.contains("generate_content"), name.contains("free_tier_requests") else { continue }
            for entry in metric["consumerQuotaLimits"] as? [[String: Any]] ?? [] {
                let unit = (entry["unit"] as? String) ?? ""
                let isDaily = unit.hasPrefix("1/d"), isMinute = unit.hasPrefix("1/min")
                guard isDaily || isMinute else { continue }
                for bucket in entry["quotaBuckets"] as? [[String: Any]] ?? [] {
                    guard let model = (bucket["dimensions"] as? [String: String])?["model"],
                          let value = (bucket["effectiveLimit"] as? String).flatMap({ Int($0) }), value > 0 else { continue }
                    var current = limits[model] ?? ModelLimit()
                    if isDaily { current.perDay = value } else { current.perMinute = value }
                    limits[model] = current
                }
            }
        }
        guard !limits.isEmpty else { return cache.limits }
        cache.limits = limits
        cache.fetchedAt = Date()
        return limits
    }

    // MARK: Usage

    /// model id -> assistant requests since midnight Pacific, from OpenCode's local database.
    private static func requestsSincePacificMidnight(databasePath: String) -> [String: Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let cutoffMillis = Int64(calendar.startOfDay(for: Date()).timeIntervalSince1970 * 1000)

        guard let rows = SQLiteReader(path: databasePath).query(
            "select json_extract(data,'$.modelID'), count(*) from message where time_created >= ?1 and json_extract(data,'$.role') = 'assistant' and json_extract(data,'$.providerID') = 'google' group by 1",
            [.int(cutoffMillis)]
        ) else { return [:] }

        var result: [String: Int] = [:]
        for row in rows {
            if let model = row[0].text, let count = row[1].int { result[model] = Int(count) }
        }
        return result
    }
}
