import Foundation
import SQLite3

/// Reads real usage/limit data straight from providers that expose it, using the
/// API key OpenCode already stores. Keys are read in-process for the duration of
/// one request, sent only over HTTPS to the provider's own host, and never logged
/// or stored. Only providers verified to report a quota are queried:
///  - OpenRouter: `GET /api/v1/key` -> `free_model_daily_requests {limit, remaining}`
///  - Cloudflare (Workers AI / AI Gateway): GraphQL analytics `aiInferenceAdaptiveGroups`
///    neurons for the UTC day, against the published free allowance. Needs the
///    token permission Account > Account Analytics > Read.
///  - Google AI Studio: see GoogleFreeTier (limits via gcloud, usage from local history)
///  - Ollama Cloud: `GET https://ollama.com/api/balance` -> included credits left of the
///    allowance, and the billing period's end (the monthly reset)
///  - Groq: a one-token chat request; the response headers carry the daily limit
///    (`x-ratelimit-limit-requests` / `x-ratelimit-remaining-requests`)
enum ProviderUsageAPI {
    private static let requestTimeout: TimeInterval = 10
    private static let groqProbeInterval: TimeInterval = 30 * 60
    /// Cloudflare's published free Workers AI allowance per UTC day. Not exposed by any API.
    private static let cloudflareFreeNeuronsPerDay = 10_000.0

    /// providerID -> quota, for the connected providers that report one.
    static func fetch(connected: [String: Set<String>], databasePath: String?) -> [String: OpenCodeUsageFetcher.Quota] {
        guard let databasePath else { return [:] }
        var result: [String: OpenCodeUsageFetcher.Quota] = [:]

        if connected["openrouter"] != nil, let key = credential(for: "openrouter", databasePath: databasePath)?["key"] as? String,
           let quota = openRouterQuota(key: key) {
            result["openrouter"] = quota
        }
        if let googleModels = connected["google"], let quota = GoogleFreeTier.quota(models: googleModels, databasePath: databasePath) {
            result["google"] = quota
        }
        for providerID in connected.keys where providerID.hasPrefix("cloudflare") {
            if let credential = credential(for: providerID, databasePath: databasePath),
               let key = credential["key"] as? String,
               let accountID = (credential["metadata"] as? [String: Any])?["accountId"] as? String,
               let quota = cloudflareQuota(key: key, accountID: accountID) {
                result[providerID] = quota
            }
        }
        if connected["ollama-cloud"] != nil, let key = credential(for: "ollama-cloud", databasePath: databasePath)?["key"] as? String,
           let quota = ollamaQuota(key: key) {
            result["ollama-cloud"] = quota
        }
        if let groqModels = connected["groq"], let key = credential(for: "groq", databasePath: databasePath)?["key"] as? String,
           let quota = groqQuota(key: key, models: groqModels) {
            result["groq"] = quota
        }
        return result
    }

    // MARK: OpenRouter

    private static func openRouterQuota(key: String) -> OpenCodeUsageFetcher.Quota? {
        guard let url = URL(string: "https://openrouter.ai/api/v1/key"),
              let (data, _) = send(URLRequest(url: url), key: key),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["data"] as? [String: Any],
              let daily = info["free_model_daily_requests"] as? [String: Any],
              let limit = (daily["limit"] as? NSNumber)?.doubleValue, limit > 0,
              let remaining = (daily["remaining"] as? NSNumber)?.doubleValue else { return nil }

        // The daily count follows the UTC day (see `usage_daily` in the same response).
        return OpenCodeUsageFetcher.Quota(label: "1d", percentLeft: percent(remaining / limit), value: nil, note: "Free-model requests per day", resetAt: nextMidnight(in: "UTC"))
    }

    // MARK: Ollama Cloud

    private static func ollamaQuota(key: String) -> OpenCodeUsageFetcher.Quota? {
        guard let url = URL(string: "https://ollama.com/api/balance"),
              let (data, _) = send(URLRequest(url: url), key: key),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let included = root["included"] as? [String: Any],
              let balance = (included["balance_usd"] as? NSNumber)?.doubleValue,
              let allowance = (included["allowance_usd"] as? NSNumber)?.doubleValue, allowance > 0 else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let until = ((included["period"] as? [String: Any])?["until"] as? String).flatMap { formatter.date(from: $0) }

        return OpenCodeUsageFetcher.Quota(
            label: "mo",
            percentLeft: percent(balance / allowance),
            value: nil,
            note: String(format: "Included credits: $%.2f of $%.2f left this billing period", balance, allowance),
            resetAt: until
        )
    }

    // MARK: Cloudflare

    private static func cloudflareQuota(key: String, accountID: String) -> OpenCodeUsageFetcher.Quota? {
        guard accountID.allSatisfy({ $0.isHexDigit }), let url = URL(string: "https://api.cloudflare.com/client/v4/graphql") else { return nil }

        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: calendar.startOfDay(for: now))
        let end = formatter.string(from: now)

        let query = "{ viewer { accounts(filter:{accountTag:\"\(accountID)\"}) { aiInferenceAdaptiveGroups(limit: 1, filter:{datetime_geq:\"\(start)\", datetime_leq:\"\(end)\"}) { sum { totalNeurons } } } } }"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])

        guard let (data, _) = send(request, key: key),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["errors"] == nil || root["errors"] is NSNull,
              let accounts = ((root["data"] as? [String: Any])?["viewer"] as? [String: Any])?["accounts"] as? [[String: Any]],
              let groups = accounts.first?["aiInferenceAdaptiveGroups"] as? [[String: Any]] else { return nil }

        // No groups means no inference today.
        let used = (groups.first?["sum"] as? [String: Any]).flatMap { ($0["totalNeurons"] as? NSNumber)?.doubleValue } ?? 0
        let left = max(0, cloudflareFreeNeuronsPerDay - used)
        return OpenCodeUsageFetcher.Quota(
            label: "1d",
            percentLeft: percent(left / cloudflareFreeNeuronsPerDay),
            value: nil,
            note: "\(Int(used)) of \(Int(cloudflareFreeNeuronsPerDay)) free neurons used today (UTC)",
            resetAt: nextMidnight(in: "UTC")
        )
    }

    // MARK: Groq

    private final class ProbeCache: @unchecked Sendable {
        let lock = NSLock()
        var quota: OpenCodeUsageFetcher.Quota?
        var fetchedAt: Date?
    }
    private static let groqCache = ProbeCache()

    /// The probe spends one request, so the result is reused for `groqProbeInterval`.
    private static func groqQuota(key: String, models: Set<String>) -> OpenCodeUsageFetcher.Quota? {
        groqCache.lock.lock()
        defer { groqCache.lock.unlock() }
        if let fetchedAt = groqCache.fetchedAt, Date().timeIntervalSince(fetchedAt) < groqProbeInterval {
            return groqCache.quota
        }

        // Skip models that are not plain chat models (moderation, speech).
        let nonChat = ["guard", "whisper", "tts", "orpheus"]
        guard let model = models.sorted().first(where: { id in !nonChat.contains { id.lowercased().contains($0) } }),
              let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]],
        ])

        var quota: OpenCodeUsageFetcher.Quota?
        if let (_, response) = send(request, key: key),
           let limit = Double(response.value(forHTTPHeaderField: "x-ratelimit-limit-requests") ?? ""), limit > 0,
           let remaining = Double(response.value(forHTTPHeaderField: "x-ratelimit-remaining-requests") ?? "") {
            let resetAt = parseDuration(response.value(forHTTPHeaderField: "x-ratelimit-reset-requests")).map { Date().addingTimeInterval($0) }
            quota = OpenCodeUsageFetcher.Quota(label: "1d", percentLeft: percent(remaining / limit), value: nil, note: "Daily request limit for \(model)", resetAt: resetAt)
        }
        groqCache.quota = quota
        groqCache.fetchedAt = Date()
        return quota
    }

    // MARK: Helpers

    /// Next midnight in the given time zone (start of the next day).
    static func nextMidnight(in zone: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
    }

    /// Parses durations like "12.342s", "2m59.56s", "1h2m3s" or "90ms" into seconds.
    private static func parseDuration(_ text: String?) -> TimeInterval? {
        guard let text, !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)(ms|h|m|s)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var total = 0.0
        var found = false
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }
            found = true
            switch text[unitRange] {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: total += value / 1000
            }
        }
        return found ? total : nil
    }

    private static func percent(_ fraction: Double) -> Int {
        max(0, min(100, Int((fraction * 100).rounded())))
    }

    /// Synchronous HTTPS request with a timeout. The key is only placed in the
    /// Authorization header of requests to the fixed provider URLs above.
    /// GET with a bearer token and optional extra headers; returns the body on HTTP 200.
    static func get(_ url: URL, bearer: String, extraHeaders: [String: String] = [:]) -> Data? {
        var request = URLRequest(url: url)
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return send(request, key: bearer)?.0
    }

    private static func send(_ request: URLRequest, key: String) -> (Data, HTTPURLResponse)? {
        guard request.url?.scheme == "https" else { return nil }
        var request = request
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        final class Box: @unchecked Sendable { var result: (Data, HTTPURLResponse)? }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse, http.statusCode == 200 {
                box.result = (data, http)
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + requestTimeout + 2) == .timedOut {
            task.cancel()
            return nil
        }
        return box.result
    }

    /// Reads one credential record (API key plus metadata) from OpenCode's credential
    /// table: read-only, parameterized query, newest row for the provider.
    private static func credential(for providerID: String, databasePath: String) -> [String: Any]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "select value from credential where integration_id = ?1 order by time_updated desc limit 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, providerID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0),
              let json = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any],
              let key = json["key"] as? String, !key.isEmpty else { return nil }
        return json
    }
}
