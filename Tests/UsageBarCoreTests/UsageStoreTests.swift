import Foundation
import Testing
@testable import UsageBarCore

@MainActor
struct UsageStoreTests {
    private struct Stub: UsageProvider {
        let sections_: [UsageSection]
        var delay: Duration = .zero
        func sections() async -> [UsageSection] {
            try? await Task.sleep(for: delay)
            return sections_
        }
    }

    private func section(_ id: String, rows: [UsageRow] = []) -> UsageSection {
        UsageSection(id: id, title: id, tint: .claude, rows: rows)
    }

    private func row(_ id: String, percent: Int, live: (@Sendable () -> Meter?)? = nil) -> UsageRow {
        UsageRow(id: id, label: id, tint: .claude,
                 content: .meters(short: nil, long: Meter(label: "1m", percentLeft: percent, reset: nil)),
                 liveMeter: live)
    }

    @Test func sectionsKeepProviderOrderEvenWhenTheyFinishOutOfOrder() async {
        let store = UsageStore(providers: [
            Stub(sections_: [section("slow")], delay: .milliseconds(80)),
            Stub(sections_: [section("fast")]),
        ], autoRefresh: false)
        await store.load()
        #expect(store.sections.map(\.id) == ["slow", "fast"])
        #expect(store.lastUpdated != nil)
        #expect(store.isRefreshing == false)
    }

    @Test func aProviderWithNothingToShowDoesNotRemoveTheOthers() async {
        let store = UsageStore(providers: [Stub(sections_: []), Stub(sections_: [section("ok")])], autoRefresh: false)
        await store.load()
        #expect(store.sections.map(\.id) == ["ok"])
    }

    @Test func liveMetersUpdateOnlyRowsThatHaveOne() async {
        let live = row("live", percent: 100, live: { Meter(label: "1m", percentLeft: 25, reset: nil) })
        let still = row("still", percent: 100)
        let store = UsageStore(providers: [Stub(sections_: [section("s", rows: [live, still])])], autoRefresh: false)
        await store.load()
        await store.updateLiveMeters()

        let rows = store.sections[0].rows
        #expect(rows[0].content == .meters(short: nil, long: Meter(label: "1m", percentLeft: 25, reset: nil)))
        #expect(rows[1].content == .meters(short: nil, long: Meter(label: "1m", percentLeft: 100, reset: nil)))
    }
}
