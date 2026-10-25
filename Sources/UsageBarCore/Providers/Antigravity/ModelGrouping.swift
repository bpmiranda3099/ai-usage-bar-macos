import Foundation

/// Turns `agy models` output into display names and assigns each model to a usage
/// group, without a fixed table.
enum ModelGrouping {
    /// `agy models` prints "<id>\t<Display Name (Effort)>" per line (plus a status
    /// line). Returns distinct display names with the effort suffix removed.
    static func displayNames(from output: String?) -> [String] {
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

    /// The group whose key is the longest prefix of the model name wins (e.g. "Gemini 4
    /// Argon"); otherwise the first group whose key mentions the model's family word
    /// (e.g. "Claude", "GPT", "Gemini"). Models matching no group are dropped.
    static func group(_ names: [String], keys: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for name in names {
            let lowered = name.lowercased()
            let prefixMatch = keys
                .filter { lowered.hasPrefix($0.lowercased()) }
                .max { $0.count < $1.count }
            let family = lowered.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? lowered
            let key = prefixMatch ?? keys.first { $0.lowercased().contains(family) }
            if let key { result[key, default: []].append(name) }
        }
        return result
    }
}
