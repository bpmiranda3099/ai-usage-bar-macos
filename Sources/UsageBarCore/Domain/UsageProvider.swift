import Foundation

/// A source of usage data. Adding a provider means conforming here and listing it in
/// `ProviderRegistry`. A provider that has nothing to show (tool missing, parse
/// failure) returns no sections rather than throwing.
protocol UsageProvider: Sendable {
    func sections() async -> [UsageSection]
}
