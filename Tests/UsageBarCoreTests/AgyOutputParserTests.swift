import Foundation
import Testing
@testable import UsageBarCore

struct AgyOutputParserTests {
    static let sample = """
    Gemini Models\tWeekly Limit Remaining\t97%\t2026-10-31T04:58:26Z
    Gemini Models\tFive Hour Limit Remaining\t98%\t2026-10-25T04:54:55Z
    Claude and GPT models\tWeekly Limit Remaining\t100%\t2026-11-01T00:14:24Z
    Claude and GPT models\tFive Hour Limit Remaining\t100%\t2026-10-25T05:14:24Z
    Gemini 4 Argon\tGemini 4 Argon Weekly Limit\t100%\t2026-11-01T00:14:24Z
    """

    @Test func groupsKeepOrderAndBothWindows() {
        let groups = AgyOutputParser.parse(Self.sample)
        #expect(groups.map(\.key) == ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"])
        #expect(groups[0].fiveHour == .init(percentLeft: 98, reset: iso("2026-10-25T04:54:55Z")))
        #expect(groups[0].weekly == .init(percentLeft: 97, reset: iso("2026-10-31T04:58:26Z")))
    }

    @Test func aGroupMayReportOnlyWeekly() {
        let argon = AgyOutputParser.parse(Self.sample)[2]
        #expect(argon.fiveHour == nil)
        #expect(argon.weekly?.percentLeft == 100)
    }

    @Test func badLinesAreSkipped() {
        let output = """
        Gemini Models\tWeekly Limit Remaining\tlots\t2026-10-31T04:58:26Z
        Gemini Models\tWeekly Limit Remaining\t50%\tnot-a-date
        short line
        Gemini Models\tWeekly Limit Remaining\t50%\t2026-10-31T04:58:26Z
        """
        let groups = AgyOutputParser.parse(output)
        #expect(groups.count == 1)
        #expect(groups[0].weekly?.percentLeft == 50)
    }

    @Test func emptyOrUnrelatedOutputGivesNoGroups() {
        #expect(AgyOutputParser.parse("").isEmpty)
        #expect(AgyOutputParser.parse("Loading...\nNo usage").isEmpty)
    }
}
