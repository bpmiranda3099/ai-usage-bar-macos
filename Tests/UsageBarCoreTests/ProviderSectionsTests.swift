import Foundation
import Testing
@testable import UsageBarCore

struct ProviderSectionsTests {
    // MARK: Antigravity

    @Test func antigravityListsGeminiThenClaudeThenOthersWithOwnTints() throws {
        // agy may report groups in any order; the section always leads with Gemini, then Claude.
        let groups = AgyOutputParser.parse(AgyOutputParserTests.sample).reversed() as [AgyGroup]
        let section = try #require(AntigravityProvider.sections(groups: groups, modelNames: []).first)
        #expect(section.id == "antigravity")
        #expect(section.rows.map(\.label) == ["Gemini Models", "Claude and GPT Models", "Gemini 4 Argon"])
        #expect(section.rows.map(\.tint) == [.antigravity, .claude, .antigravity])
    }

    @Test func antigravityRowsCarryTheirModelsAsTooltips() throws {
        let section = try #require(AntigravityProvider.sections(
            groups: AgyOutputParser.parse(AgyOutputParserTests.sample),
            modelNames: ["Gemini 3.8 Flash", "Claude Opus 5.5", "Gemini 4 Argon"]
        ).first)
        #expect(section.rows[0].tooltip == ["Gemini 3.8 Flash"])
        #expect(section.rows[1].tooltip == ["Claude Opus 5.5"])
        #expect(section.rows[2].tooltip == ["Gemini 4 Argon"])
    }

    @Test func antigravityWeeklyOnlyGroupHasOnlyALongMeter() throws {
        let sections = AntigravityProvider.sections(groups: AgyOutputParser.parse(AgyOutputParserTests.sample), modelNames: [])
        guard case .meters(let short, let long) = try #require(sections.first?.rows.last?.content) else {
            Issue.record("expected meters"); return
        }
        #expect(short == nil)
        #expect(long?.label == "wk")
    }

    @Test func antigravityWithNoGroupsHasNoSection() {
        #expect(AntigravityProvider.sections(groups: [], modelNames: ["Gemini"]).isEmpty)
    }

    // MARK: Claude Code

    private let claudeUsage = ClaudeUsageParser.parseUsage("""
    Current session: 5% used · resets Oct 25 at 12:30pm (Asia/Manila)
    Current week (all models): 17% used · resets Oct 29 at 10am (Asia/Manila)
    Current week (Fable): 0% used · resets Oct 29 at 10am (Asia/Manila)
    """, now: iso("2026-10-25T00:00:00Z"))

    @Test func claudeHasAMainRowAndOnePerModelRow() throws {
        let section = try #require(ClaudeCodeProvider.sections(usage: claudeUsage, models: ["Sonnet", "Fable"]).first)
        #expect(section.id == "claude")
        #expect(section.rows.map(\.label) == ["Claude Models", "Claude Fable"])
        #expect(section.rows[0].tooltip == ["Sonnet", "Fable"])
        #expect(section.rows[1].tooltip == ["Fable"])
        guard case .meters(let short, let long) = section.rows[0].content else { Issue.record("expected meters"); return }
        #expect(short?.percentLeft == 95)
        #expect(long?.percentLeft == 83)
    }

    @Test func claudeWithoutUsageHasNoSection() {
        #expect(ClaudeCodeProvider.sections(usage: nil, models: ["Sonnet"]).isEmpty)
    }

    // MARK: OpenCode

    private func provider(
        _ id: String, name: String, labels: [String] = ["model-a"], week: Int = 0, total: Int = 0,
        lastMinute: Int = 0, quota: OpenCodeUsageFetcher.Quota? = nil
    ) -> OpenCodeUsageFetcher.ProviderUsage {
        .init(id: id, name: name, modelLabels: labels, requestsToday: 0, requestsWeek: week,
              requestsLastMinute: lastMinute, rateResetAt: nil, totalRequests: total, lastUsed: nil, quota: quota)
    }

    @Test func openCodeSplitsMeterRowsFromTheOtherProvidersRow() throws {
        let quota = OpenCodeUsageFetcher.Quota(label: "1d", percentLeft: 80, note: "note", resetAt: iso("2026-10-26T00:00:00Z"))
        let section = try #require(OpenCodeProvider.sections(from: [
            provider("openrouter", name: "OpenRouter", quota: quota),
            provider("nvidia", name: "Nvidia", lastMinute: 10),
            provider("modal", name: "Modal"),
            provider("neon", name: "Neon"),
        ], perMinuteLimits: ["nvidia": 40]).first)

        #expect(section.id == "openCode")
        #expect(section.rows.map(\.label) == ["OpenRouter", "Nvidia", "Other providers"])
        #expect(section.rows[0].tooltip.first == "note")
        guard case .text(let others) = section.rows[2].content else { Issue.record("expected text"); return }
        #expect(others == "Modal, Neon")
    }

    @Test func perMinuteRowCountsAgainstItsLimitAndIsLive() throws {
        let section = try #require(OpenCodeProvider.sections(
            from: [provider("nvidia", name: "Nvidia", lastMinute: 10)], perMinuteLimits: ["nvidia": 40]
        ).first)
        let row = section.rows[0]
        guard case .meters(_, let long) = row.content else { Issue.record("expected meters"); return }
        #expect(long == Meter(label: "1m", percentLeft: 75, reset: nil))
        #expect(row.liveMeter != nil)
    }

    @Test func tooltipListsAreCapped() throws {
        let many = (1...20).map { "model-\($0)" }
        let section = try #require(OpenCodeProvider.sections(from: [provider("modal", name: "Modal", labels: many)]).first)
        let lines = section.rows[0].tooltip
        #expect(lines.contains("  model-15"))
        #expect(!lines.contains("  model-16"))
        #expect(lines.contains("  +5 more"))
    }

    @Test func noProvidersMeansNoSection() {
        #expect(OpenCodeProvider.sections(from: []).isEmpty)
    }

    @Test func quotaWindowNamesAreAbbreviated() {
        #expect(OpenCodeProvider.windowLabel("Monthly") == "mo")
        #expect(OpenCodeProvider.windowLabel("Weekly") == "wk")
        #expect(OpenCodeProvider.windowLabel("Daily") == "1d")
        #expect(OpenCodeProvider.windowLabel("1d") == "1d")
        #expect(OpenCodeProvider.windowLabel(nil) == "–")
    }
}
