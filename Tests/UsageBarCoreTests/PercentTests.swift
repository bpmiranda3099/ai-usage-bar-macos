import Testing
@testable import UsageBarCore

struct PercentTests {
    @Test func clampKeepsValuesInRange() {
        #expect(Percent.clamped(-5) == 0)
        #expect(Percent.clamped(42) == 42)
        #expect(Percent.clamped(250) == 100)
    }

    @Test func fractionsBecomeRoundedPercents() {
        #expect(Percent.fromFraction(0) == 0)
        #expect(Percent.fromFraction(0.5) == 50)
        #expect(Percent.fromFraction(0.126) == 13)
        #expect(Percent.fromFraction(1.5) == 100)
        #expect(Percent.fromFraction(-1) == 0)
    }

    @Test func remainingAfterUseIsClamped() {
        #expect(Percent.remaining(used: 12, limit: 20) == 40)
        #expect(Percent.remaining(used: 25, limit: 20) == 0)
        #expect(Percent.remaining(used: 0, limit: 20) == 100)
    }

    @Test func aNonPositiveLimitLeavesNothing() {
        #expect(Percent.remaining(used: 1, limit: 0) == 0)
        #expect(Percent.remaining(used: 0, limit: -3) == 0)
    }
}
