import Foundation
import Testing
@testable import UsageBarCore

struct ResetAndPercentTests {
    @Test func durationsParseAllUnits() throws {
        #expect(try #require(ProviderUsageAPI.parseDuration("12.342s")) == 12.342)
        #expect(try #require(ProviderUsageAPI.parseDuration("2m59.56s")) == 179.56)
        #expect(try #require(ProviderUsageAPI.parseDuration("1h2m3s")) == 3723)
        #expect(try #require(ProviderUsageAPI.parseDuration("90ms")) == 0.09)
    }

    @Test func badDurationsAreNil() {
        #expect(ProviderUsageAPI.parseDuration(nil) == nil)
        #expect(ProviderUsageAPI.parseDuration("") == nil)
        #expect(ProviderUsageAPI.parseDuration("soon") == nil)
    }

    @Test func nextMidnightFollowsTheGivenTimeZone() {
        let now = iso("2026-10-25T10:00:00Z")
        #expect(ProviderUsageAPI.nextMidnight(in: "UTC", after: now) == iso("2026-10-26T00:00:00Z"))
        // Pacific is still on daylight time until Nov 1 (UTC-7).
        #expect(ProviderUsageAPI.nextMidnight(in: "America/Los_Angeles", after: now) == iso("2026-10-26T07:00:00Z"))
    }
}
