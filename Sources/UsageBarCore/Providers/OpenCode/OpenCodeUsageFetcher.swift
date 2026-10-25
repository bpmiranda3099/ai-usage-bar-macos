import Foundation

/// Usage for OpenCode's connected providers. Everything is read at runtime,
/// nothing is hardcoded per model or provider:
///  - connected providers/models: `opencode models`
///  - which models are free: OpenCode's own catalog (`models.json`, cost 0)
///  - usage: `opencode stats --models --json` (local request counts) and, where a
///    provider reports one, the provider's own API (see ProviderUsageAPI)

enum OpenCodeUsageFetcher {
    /// Per-minute request caps for providers that publish no usage API. These are
    /// not provider-reported values (NVIDIA's ~40 RPM is a community-observed
    /// baseline that varies by model); the meter counts requests made through
    /// OpenCode on this Mac against them.
    static let perMinuteLimits: [String: Int] = ["nvidia": 40]
    private static let rateWindow: TimeInterval = 60

    struct Quota {
        let label: String?
        let percentLeft: Int?
        /// Extra context for the tooltip (e.g. which model a limit applies to).
        var note: String? = nil
        /// When the window resets, if the provider (or its documented schedule) says so.
        var resetAt: Date? = nil
    }

    struct ProviderUsage {
        let id: String
        let name: String
        /// Tooltip lines: free models first (marked when the provider also has priced ones).
        let modelLabels: [String]
        let requestsToday: Int
        let requestsWeek: Int
        /// All-time requests and last activity from OpenCode's local history.
        let requestsLastMinute: Int
        /// The next minute boundary, when the per-minute count resets.
        let rateResetAt: Date?
        let totalRequests: Int
        let lastUsed: Date?
        let quota: Quota?
    }

    static func fetch() -> [ProviderUsage] {
        guard let connected = connectedModels(), !connected.isEmpty else { return [] }

        let catalog = providerCatalog(connected: connected)
        guard !catalog.isEmpty else { return [] }

        let todayCounts = requestCounts(days: 0)
        let weekCounts = requestCounts(days: 7)
        let history = providerHistory()
        let apiQuotas = ProviderUsageAPI.fetch(connected: connected, databasePath: OpenCodePaths.database)

        return catalog.keys.sorted { catalog[$0]!.name.localizedCaseInsensitiveCompare(catalog[$1]!.name) == .orderedAscending }.map { id in
            let provider = catalog[id]!
            let modelIDs = provider.modelIDs
            func total(_ counts: [String: [String: Int]]) -> Int {
                (counts[id] ?? [:]).filter { modelIDs.contains($0.key) }.values.reduce(0, +)
            }
            return ProviderUsage(
                id: id,
                name: provider.name,
                modelLabels: provider.labels,
                requestsToday: total(todayCounts),
                requestsWeek: total(weekCounts),
                requestsLastMinute: perMinuteLimits[id] == nil ? 0 : (requestsInLastMinute(providerID: id)?.count ?? 0),
                rateResetAt: perMinuteLimits[id] == nil ? nil : requestsInLastMinute(providerID: id)?.resetAt,
                totalRequests: history[id]?.count ?? 0,
                lastUsed: history[id]?.lastUsed,
                quota: apiQuotas[id]
            )
        }
    }

    // MARK: Models

    /// provider id -> model ids, from `opencode models` ("provider/model" per line;
    /// model ids may themselves contain slashes).
    private static func connectedModels() -> [String: Set<String>]? {
        guard let output = Tool.opencode.run(["models"]) else { return nil }
        var result: [String: Set<String>] = [:]
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let slash = text.firstIndex(of: "/") else { continue }
            let provider = String(text[..<slash])
            let model = String(text[text.index(after: slash)...])
            guard !provider.contains(" "), !model.isEmpty else { continue }
            result[provider, default: []].insert(model)
        }
        return result
    }

    private struct CatalogProvider {
        let name: String
        let modelIDs: Set<String>
        let labels: [String]
    }

    /// Every connected provider with its models; models the catalog lists at zero
    /// input and output cost are free (a missing cost is unknown, not free).
    private static func providerCatalog(connected: [String: Set<String>]) -> [String: CatalogProvider] {
        guard let data = FileManager.default.contents(atPath: OpenCodePaths.modelCatalog),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }

        var result: [String: CatalogProvider] = [:]
        for (providerID, modelIDs) in connected {
            guard let provider = root[providerID] as? [String: Any],
                  let models = provider["models"] as? [String: Any] else { continue }

            var ids = Set<String>()
            var free: [String] = []
            var paid: [String] = []
            for modelID in modelIDs.sorted() {
                guard let model = models[modelID] as? [String: Any] else { continue }
                ids.insert(modelID)
                let name = model["name"] as? String ?? modelID
                let cost = model["cost"] as? [String: Any]
                if (cost?["input"] as? NSNumber)?.doubleValue == 0, (cost?["output"] as? NSNumber)?.doubleValue == 0 {
                    free.append(name)
                } else {
                    paid.append(name)
                }
            }
            guard !ids.isEmpty else { continue }
            // Providers with any free model list only those; a provider with none lists
            // its models so the tooltip isn't blank.
            let labels = free.isEmpty ? paid : free
            result[providerID] = CatalogProvider(name: provider["name"] as? String ?? providerID, modelIDs: ids, labels: labels)
        }
        return result
    }

    // MARK: Usage

    /// provider id -> model id -> request (step) count for the last `days` days (0 = today).
    private static func requestCounts(days: Int) -> [String: [String: Int]] {
        guard let output = Tool.opencode.run(["stats", "--days", String(days), "--models", "--json"]),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [:] }

        var result: [String: [String: Int]] = [:]
        for entry in models {
            guard let model = entry["model"] as? [String: Any],
                  let provider = model["providerID"] as? String,
                  let id = model["id"] as? String,
                  let steps = entry["steps"] as? Int else { continue }
            result[provider, default: [:]][id, default: 0] += steps
        }
        return result
    }

    /// All-time assistant request count and last activity per provider, read-only
    /// from OpenCode's local database (only provider id and timestamps are selected).
    private static func providerHistory() -> [String: (count: Int, lastUsed: Date)] {
        guard let path = OpenCodePaths.database,
              let rows = SQLiteReader(path: path).query("""
                  select json_extract(data,'$.providerID'), count(*), max(time_created)
                  from message where json_extract(data,'$.role') = 'assistant' group by 1
                  """) else { return [:] }

        var result: [String: (count: Int, lastUsed: Date)] = [:]
        for row in rows {
            guard let provider = row[0].text, let count = row[1].int, let millis = row[2].int else { continue }
            result[provider] = (Int(count), Date(timeIntervalSince1970: Double(millis) / 1000))
        }
        return result
    }

    /// Assistant requests for one provider in the current clock minute, plus the next
    /// minute boundary, from OpenCode's local database. Cheap enough to call every few seconds.
    static func requestsInLastMinute(providerID: String) -> (count: Int, resetAt: Date?)? {
        guard let path = OpenCodePaths.database else { return nil }

        let minuteStart = (Date().timeIntervalSince1970 / rateWindow).rounded(.down) * rateWindow
        guard let rows = SQLiteReader(path: path).query(
            "select count(*) from message where time_created >= ?1 and json_extract(data,'$.role') = 'assistant' and json_extract(data,'$.providerID') = ?2",
            [.int(Int64(minuteStart * 1000)), .text(providerID)]
        ), let count = rows.first?[0].int else { return nil }
        return (Int(count), Date(timeIntervalSince1970: minuteStart + rateWindow))
    }
}
