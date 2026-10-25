import Foundation
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published var entries: [UsageEntry] = []
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var timerCancellable: AnyCancellable?
    private let refreshInterval: TimeInterval = 5 * 60

    public init() {
        refresh()
        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    /// Recomputes rolling per-minute meters from local history only (no network),
    /// so they track live while the panel is open.
    public func refreshRateMeters() {
        let targets = entries.compactMap { entry -> (id: String, provider: String, limit: Int)? in
            guard let provider = entry.rateProviderID, let limit = entry.rateLimitPerMinute else { return nil }
            return (entry.id, provider, limit)
        }
        guard !targets.isEmpty else { return }
        Task {
            let counts = await Task.detached(priority: .utility) {
                targets.map { OpenCodeUsageFetcher.requestsInLastMinute(providerID: $0.provider) }
            }.value
            for (target, result) in zip(targets, counts) {
                guard let result, let index = entries.firstIndex(where: { $0.id == target.id }) else { continue }
                let percent = UsageEntry.percentLeft(used: result.count, limit: target.limit)
                if entries[index].weeklyPercent != percent || entries[index].weeklyReset != result.resetAt {
                    entries[index] = entries[index].withWeekly(percent: percent, reset: result.resetAt)
                }
            }
        }
    }

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer {
                self.isRefreshing = false
            }
            // UsageFetcher.fetch() already runs its agy/Claude Code lookups
            // concurrently on their own detached tasks internally.
            let fetched = await UsageFetcher.fetch()
            self.entries = fetched
            self.lastUpdated = Date()
        }
    }
}
