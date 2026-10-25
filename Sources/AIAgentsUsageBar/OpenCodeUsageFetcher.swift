import Foundation

/// Usage for OpenCode's connected providers. Everything is read at runtime,
/// nothing is hardcoded per model or provider:
///  - connected providers/models: `opencode models`
///  - which models are free: OpenCode's own catalog (`models.json`, cost 0)
///  - usage: `opencode stats --models --json` (local request counts) and, where a
///    provider reports a quota, `opencode-quota show` (live, no config needed)
import SQLite3

enum OpenCodeUsageFetcher {
    /// Per-minute request caps for providers that publish no usage API. These are
    /// not provider-reported values (NVIDIA's ~40 RPM is a community-observed
    /// baseline that varies by model); the meter counts requests made through
    /// OpenCode on this Mac against them.
    static let perMinuteLimits: [String: Int] = ["nvidia": 40]
    private static let rateWindow: TimeInterval = 60

    private final class PathCache: @unchecked Sendable {
        let lock = NSLock()
        var databasePath: String?
    }
    private static let pathCache = PathCache()

    struct Quota {
        let label: String?
        let percentLeft: Int?
        let value: String?
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
        guard let opencode = executable(["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode", "\(NSHomeDirectory())/.opencode/bin/opencode", "\(NSHomeDirectory())/.local/bin/opencode"]),
              let connected = connectedModels(opencode: opencode), !connected.isEmpty else { return [] }

        let catalog = providerCatalog(opencode: opencode, connected: connected)
        guard !catalog.isEmpty else { return [] }

        let todayCounts = requestCounts(opencode: opencode, days: 0)
        let weekCounts = requestCounts(opencode: opencode, days: 7)
        let quotas = fetchQuotas()
        let history = providerHistory(opencode: opencode)
        let apiQuotas = ProviderUsageAPI.fetch(connected: connected, databasePath: databasePath(opencode: opencode))

        return catalog.keys.sorted { catalog[$0]!.name.localizedCaseInsensitiveCompare(catalog[$1]!.name) == .orderedAscending }.map { id in
            let provider = catalog[id]!
            let modelIDs = provider.modelIDs
            func total(_ counts: [String: [String: Int]]) -> Int {
                (counts[id] ?? [:]).filter { modelIDs.contains($0.key) }.values.reduce(0, +)
            }
            let lowered = provider.name.lowercased()
            let quota = quotas[lowered] ?? quotas.first { $0.key.contains(lowered) || lowered.contains($0.key) }?.value
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
                quota: apiQuotas[id] ?? quota
            )
        }
    }

    // MARK: Models

    /// provider id -> model ids, from `opencode models` ("provider/model" per line;
    /// model ids may themselves contain slashes).
    private static func connectedModels(opencode: String) -> [String: Set<String>]? {
        guard let output = SubprocessRunner.run(executablePath: opencode, arguments: ["models"]) else { return nil }
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
    private static func providerCatalog(opencode: String, connected: [String: Set<String>]) -> [String: CatalogProvider] {
        guard let data = FileManager.default.contents(atPath: catalogPath(opencode: opencode)),
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

    private static func catalogPath(opencode: String) -> String {
        let fallback = "\(NSHomeDirectory())/.cache/opencode/models.json"
        guard let output = SubprocessRunner.run(executablePath: opencode, arguments: ["debug", "paths"]) else { return fallback }
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2, parts[0] == "cache" {
                return parts[1].trimmingCharacters(in: .whitespaces) + "/models.json"
            }
        }
        return fallback
    }

    // MARK: Usage

    /// provider id -> model id -> request (step) count for the last `days` days (0 = today).
    private static func requestCounts(opencode: String, days: Int) -> [String: [String: Int]] {
        guard let output = SubprocessRunner.run(executablePath: opencode, arguments: ["stats", "--days", String(days), "--models", "--json"]),
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
    private static func providerHistory(opencode: String) -> [String: (count: Int, lastUsed: Date)] {
        guard let sqlite = executable(["/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3"]),
              let dbPath = databasePath(opencode: opencode),
              FileManager.default.fileExists(atPath: dbPath) else { return [:] }

        let query = "select json_extract(data,'$.providerID'), count(*), max(time_created) from message where json_extract(data,'$.role')='assistant' group by 1;"
        guard let output = SubprocessRunner.run(executablePath: sqlite, arguments: ["-readonly", "-separator", "|", dbPath, query]) else { return [:] }

        var result: [String: (count: Int, lastUsed: Date)] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: "|").map(String.init)
            guard cols.count == 3, let count = Int(cols[1]), let millis = Double(cols[2]) else { continue }
            result[cols[0]] = (count, Date(timeIntervalSince1970: millis / 1000))
        }
        return result
    }

    /// Assistant requests for one provider in the current clock minute, plus the next
    /// minute boundary, from OpenCode's local database (read-only, parameterized).
    /// Cheap enough to call every few seconds.
    static func requestsInLastMinute(providerID: String) -> (count: Int, resetAt: Date?)? {
        pathCache.lock.lock()
        let path = pathCache.databasePath
        pathCache.lock.unlock()
        guard let path else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "select count(*) from message where time_created >= ?1 and json_extract(data,'$.role') = 'assistant' and json_extract(data,'$.providerID') = ?2"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let minuteStart = (Date().timeIntervalSince1970 / rateWindow).rounded(.down) * rateWindow
        let cutoffMillis = Int64(minuteStart * 1000)
        sqlite3_bind_int64(statement, 1, cutoffMillis)
        sqlite3_bind_text(statement, 2, providerID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (Int(sqlite3_column_int64(statement, 0)), Date(timeIntervalSince1970: minuteStart + rateWindow))
    }

    private static func databasePath(opencode: String) -> String? {
        if let output = SubprocessRunner.run(executablePath: opencode, arguments: ["debug", "paths"]) {
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2, parts[0] == "db" {
                    let path = parts[1].trimmingCharacters(in: .whitespaces)
                    pathCache.lock.lock()
                    pathCache.databasePath = path
                    pathCache.lock.unlock()
                    return path
                }
            }
        }
        return nil
    }

    // MARK: Quota

    /// Parses `opencode-quota show`, e.g.
    ///   [Ollama Cloud] Monthly
    ///   ████████░░  100% left
    ///   [OpenRouter]                        $0.00
    /// Keyed by lowercased provider name; only the first window per provider is kept.
    private static func fetchQuotas() -> [String: Quota] {
        // The CLI is a `#!/usr/bin/env node` script and the LaunchAgent's PATH has no
        // node, so launch node explicitly with the script path.
        guard let tool = executable(["/opt/homebrew/bin/opencode-quota", "/usr/local/bin/opencode-quota"]),
              let node = executable(["/opt/homebrew/bin/node", "/usr/local/bin/node"]),
              let output = SubprocessRunner.run(executablePath: node, arguments: [tool, "show"]) else { return [:] }

        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String: Quota] = [:]
        for (index, line) in lines.enumerated() {
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let provider = String(line[line.index(after: line.startIndex)..<close]).lowercased()
            guard result[provider] == nil else { continue }

            let rest = line[line.index(after: close)...]
            let columns = rest.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            var percent: Int?
            if index + 1 < lines.count, let range = lines[index + 1].range(of: #"(\d{1,3})%\s+left"#, options: .regularExpression) {
                percent = Int(lines[index + 1][range].prefix(while: { $0.isNumber }))
            }

            if percent != nil {
                result[provider] = Quota(label: columns.first, percentLeft: percent, value: nil)
            } else if let value = columns.last {
                result[provider] = Quota(label: columns.count > 1 ? columns.first : nil, percentLeft: nil, value: value)
            }
        }
        return result
    }

    private static func executable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
