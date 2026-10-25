import Foundation
import Testing
@testable import UsageBarCore

struct ClaudeUsageParserTests {
    private let now = iso("2026-10-25T00:00:00Z")

    private let sample = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 5% used · resets Oct 25 at 12:30pm (Asia/Manila)
    Current week (all models): 17% used · resets Oct 29 at 10am (Asia/Manila)
    Current week (Fable): 0% used · resets Oct 29 at 10am (Asia/Manila)

    Last 24h · 71 requests · 3 sessions
    """

    @Test func parsesSessionWeekAndPerModelLines() throws {
        let result = try #require(ClaudeCodeUsageFetcher.parseUsage(sample, now: now))
        #expect(result.fiveHourPercent == 95)
        #expect(result.weeklyPercent == 83)
        #expect(result.fiveHourReset == iso("2026-10-25T04:30:00Z"))
        #expect(result.weeklyReset == iso("2026-10-29T02:00:00Z"))
        #expect(result.extraWeekly.map(\.name) == ["Fable"])
        #expect(result.extraWeekly.first?.percent == 100)
    }

    @Test func plansWithoutPerModelLinesHaveNoExtras() throws {
        let output = """
        Current session: 5% used · resets Oct 25 at 12:30pm (Asia/Manila)
        Current week (all models): 17% used · resets Oct 29 at 10am (Asia/Manila)
        """
        let result = try #require(ClaudeCodeUsageFetcher.parseUsage(output, now: now))
        #expect(result.extraWeekly.isEmpty)
    }

    @Test func aResetThatAlreadyPassedRollsForwardOneDayForTheSession() throws {
        let output = """
        Current session: 5% used · resets Oct 24 at 1am (Asia/Manila)
        Current week (all models): 17% used · resets Oct 29 at 10am (Asia/Manila)
        """
        let result = try #require(ClaudeCodeUsageFetcher.parseUsage(output, now: now))
        // Oct 24 01:00 Manila = Oct 23 17:00Z, already past, so +1 day.
        #expect(result.fiveHourReset == iso("2026-10-24T17:00:00Z"))
    }

    @Test func missingWeekLineReturnsNil() {
        let output = "Current session: 5% used · resets Oct 25 at 12:30pm (Asia/Manila)"
        #expect(ClaudeCodeUsageFetcher.parseUsage(output, now: now) == nil)
    }

    @Test func garbageReturnsNil() {
        #expect(ClaudeCodeUsageFetcher.parseUsage("", now: now) == nil)
        #expect(ClaudeCodeUsageFetcher.parseUsage("Current session: lots\nCurrent week: some", now: now) == nil)
    }

    @Test func modelListKeepsRealModelsAndDropsSelectors() {
        let output = """
        Current model: `Sonnet 5.5`
        Usage: /model <name>. Available: sonnet, opus, haiku, fable, best, sonnet[1m], opus[1m], fable[1m], opusplan, default, or a full model ID.
        """
        #expect(ClaudeCodeUsageFetcher.parseModels(output) == ["Sonnet", "Opus", "Haiku", "Fable"])
    }

    @Test func modelListWithoutAvailableLineIsEmpty() {
        #expect(ClaudeCodeUsageFetcher.parseModels("nothing useful here").isEmpty)
    }
}
