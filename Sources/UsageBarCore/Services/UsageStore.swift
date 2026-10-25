import Foundation
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published private(set) var sections: [UsageSection] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    private let providers: [any UsageProvider]
    private var timerCancellable: AnyCancellable?
    private let refreshInterval: TimeInterval = 5 * 60

    public convenience init() {
        self.init(providers: ProviderRegistry.all, autoRefresh: true)
    }

    init(providers: [any UsageProvider], autoRefresh: Bool) {
        self.providers = providers
        guard autoRefresh else { return }
        refresh()
        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    public func refresh() {
        guard !isRefreshing else { return }
        Task { await load() }
    }

    /// Fetches every provider concurrently and keeps sections in provider order.
    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = providers
        let results = await withTaskGroup(of: (Int, [UsageSection]).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await provider.sections()) }
            }
            var collected: [(Int, [UsageSection])] = []
            for await result in group { collected.append(result) }
            return collected
        }
        sections = results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        lastUpdated = Date()
    }

    /// Recomputes live meters (rows with a `liveMeter`) from local data only, no
    /// network, so they track usage while the panel is open.
    public func refreshLiveMeters() {
        Task { await updateLiveMeters() }
    }

    func updateLiveMeters() async {
        let targets = sections.flatMap { section in
            section.rows.compactMap { row in row.liveMeter.map { (section.id, row.id, $0) } }
        }
        guard !targets.isEmpty else { return }

        let meters = await inBackground { targets.map { $0.2() } }
        for (target, meter) in zip(targets, meters) {
            guard let meter,
                  let s = sections.firstIndex(where: { $0.id == target.0 }),
                  let r = sections[s].rows.firstIndex(where: { $0.id == target.1 }) else { continue }
            let updated = sections[s].rows[r].replacingLongMeter(meter)
            if updated.content != sections[s].rows[r].content {
                sections[s].rows[r] = updated
            }
        }
    }
}
