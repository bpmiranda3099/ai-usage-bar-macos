import Foundation

/// OpenCode's data and cache locations, read once from `opencode debug paths`
/// (lines look like "db    /Users/me/.local/share/opencode/opencode.db").
enum OpenCodePaths {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var paths: [String: String]?
    }
    private static let cache = Cache()

    /// The SQLite history database, if OpenCode reports one.
    static var database: String? { value(for: "db") }

    /// The model catalog cache file, with the default location as a fallback.
    static var modelCatalog: String {
        let directory = value(for: "cache") ?? "\(NSHomeDirectory())/.cache/opencode"
        return directory + "/models.json"
    }

    static func parse(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 { result[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    private static func value(for key: String) -> String? {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if cache.paths == nil, let output = Tool.opencode.run(["debug", "paths"]) {
            cache.paths = parse(output)
        }
        return cache.paths?[key]
    }
}
