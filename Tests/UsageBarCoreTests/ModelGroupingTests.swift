import Testing
@testable import UsageBarCore

struct ModelGroupingTests {
    @Test func effortSuffixIsRemovedAndNamesAreDeduplicated() {
        let output = """
        Fetching available models...
        gemini-4-argon-medium\tGemini 4 Argon (Medium)
        gemini-4-argon-high\tGemini 4 Argon (High)
        claude-opus-5-5-low\tClaude Opus 5.5 (Low)
        """
        #expect(UsageFetcher.parseModelNames(output) == ["Gemini 4 Argon", "Claude Opus 5.5"])
    }

    @Test func noOutputGivesNoModels() {
        #expect(UsageFetcher.parseModelNames(nil).isEmpty)
        #expect(UsageFetcher.parseModelNames("").isEmpty)
    }

    @Test func modelsJoinTheLongestMatchingGroupThenTheirFamily() {
        let groups = ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"]
        let names = ["Gemini 4 Argon", "Gemini 3.8 Flash", "Claude Opus 5.5", "GPT-OSS 120B"]
        let result = UsageFetcher.groupModels(names, groupKeys: groups)
        #expect(result["Gemini 4 Argon"] == ["Gemini 4 Argon"])
        #expect(result["Gemini Models"] == ["Gemini 3.8 Flash"])
        #expect(result["Claude and GPT models"] == ["Claude Opus 5.5", "GPT-OSS 120B"])
    }

    @Test func aModelWithNoMatchingGroupIsDropped() {
        let result = UsageFetcher.groupModels(["Mystery 1"], groupKeys: ["Gemini Models"])
        #expect(result.isEmpty)
    }
}
