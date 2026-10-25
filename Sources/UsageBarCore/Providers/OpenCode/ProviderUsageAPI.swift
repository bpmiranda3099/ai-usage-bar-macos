import Foundation

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
              let data = HTTPClient.shared.get(url, bearer: key)?.body,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["data"] as? [String: Any],
              let daily = info["free_model_daily_requests"] as? [String: Any],
              let limit = (daily["limit"] as? NSNumber)?.doubleValue, limit > 0,
              let remaining = (daily["remaining"] as? NSNumber)?.doubleValue else { return nil }

        // The daily count follows the UTC day (see `usage_daily` in the same response).
        return OpenCodeUsageFetcher.Quota(label: "1d", percentLeft: Percent.fromFraction(remaining / limit), note: "Free-model requests per day", resetAt: nextMidnight(in: "UTC"))
    }

    // MARK: Ollama Cloud

    private static func ollamaQuota(key: String) -> OpenCodeUsageFetcher.Quota? {
        guard let url = URL(string: "https://ollama.com/api/balance"),
              let data = HTTPClient.shared.get(url, bearer: key)?.body,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let included = root["included"] as? [String: Any],
              let balance = (included["balance_usd"] as? NSNumber)?.doubleValue,
              let allowance = (included["allowance_usd"] as? NSNumber)?.doubleValue, allowance > 0 else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let until = ((included["period"] as? [String: Any])?["until"] as? String).flatMap { formatter.date(from: $0) }

        return OpenCodeUsageFetcher.Quota(
            label: "mo",
            percentLeft: Percent.fromFraction(balance / allowance),
            note: String(format: "Included credits: $%.2f of $%.2f left this billing period", balance, allowance),
            resetAt: until
        )
    }

    // MARK: Cloudflare

    private static func cloudflareQuota(key: String, accountID: String) -> OpenCodeUsageFetcher.Quota? {
        guard !accountID.isEmpty, let url = URL(string: "https://api.cloudflare.com/client/v4/graphql") else { return nil }

        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let formatter = ISO8601DateFormatter()

        // Values travel as GraphQL variables, never spliced into the query text.
        let query = """
            query($account: String!, $start: Time!, $end: Time!) {
              viewer { accounts(filter: { accountTag: $account }) {
                aiInferenceAdaptiveGroups(limit: 1, filter: { datetime_geq: $start, datetime_leq: $end }) { sum { totalNeurons } }
              } }
            }
            """
        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "account": accountID,
                "start": formatter.string(from: calendar.startOfDay(for: now)),
                "end": formatter.string(from: now),
            ],
        ]

        guard let data = HTTPClient.shared.post(url, json: payload, bearer: key)?.body,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["errors"] == nil || root["errors"] is NSNull,
              let accounts = ((root["data"] as? [String: Any])?["viewer"] as? [String: Any])?["accounts"] as? [[String: Any]],
              let groups = accounts.first?["aiInferenceAdaptiveGroups"] as? [[String: Any]] else { return nil }

        // No groups means no inference today.
        let rawUsed = (groups.first?["sum"] as? [String: Any]).flatMap { ($0["totalNeurons"] as? NSNumber)?.doubleValue } ?? 0
        let used = rawUsed.isFinite ? min(max(0, rawUsed), 1e12) : 0
        let left = max(0, cloudflareFreeNeuronsPerDay - used)
        return OpenCodeUsageFetcher.Quota(
            label: "1d",
            percentLeft: Percent.fromFraction(left / cloudflareFreeNeuronsPerDay),
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

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]],
        ]

        var quota: OpenCodeUsageFetcher.Quota?
        if let response = HTTPClient.shared.post(url, json: payload, bearer: key)?.http,
           let limit = Double(response.value(forHTTPHeaderField: "x-ratelimit-limit-requests") ?? ""), limit > 0,
           let remaining = Double(response.value(forHTTPHeaderField: "x-ratelimit-remaining-requests") ?? "") {
            let resetAt = parseDuration(response.value(forHTTPHeaderField: "x-ratelimit-reset-requests")).map { Date().addingTimeInterval($0) }
            quota = OpenCodeUsageFetcher.Quota(label: "1d", percentLeft: Percent.fromFraction(remaining / limit), note: "Daily request limit for \(model)", resetAt: resetAt)
        }
        groqCache.quota = quota
        groqCache.fetchedAt = Date()
        return quota
    }

    // MARK: Helpers

    /// Next midnight in the given time zone (start of the next day).
    static func nextMidnight(in zone: String, after now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }

    /// Parses durations like "12.342s", "2m59.56s", "1h2m3s" or "90ms" into seconds.
    static func parseDuration(_ text: String?) -> TimeInterval? {
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
        // Provider headers can say "inf" or huge numbers; cap at 30 days.
        return found && total.isFinite ? min(total, 30 * 86_400) : nil
    }


    /// Reads one credential record (API key plus metadata) from OpenCode's credential
    /// table: read-only, parameterized query, newest row for the provider.
    private static func credential(for providerID: String, databasePath: String) -> [String: Any]? {
        guard let rows = SQLiteReader(path: databasePath).query(
            "select value from credential where integration_id = ?1 order by time_updated desc limit 1",
            [.text(providerID)]
        ), let raw = rows.first?[0].text,
              let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let key = json["key"] as? String, !key.isEmpty else { return nil }
        return json
    }
}
