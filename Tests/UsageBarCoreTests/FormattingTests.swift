import Foundation
import Testing
@testable import UsageBarCore

@MainActor
struct FormattingTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func countdownUnderAMinuteShowsSeconds() {
        #expect(Formatting.countdown(to: now.addingTimeInterval(45), from: now) == "45s")
    }

    @Test func countdownShowsDaysHoursAndMinutes() {
        let target = now.addingTimeInterval((2 * 24 + 3) * 3600 + 4 * 60)
        #expect(Formatting.countdown(to: target, from: now) == "2d 3h 4m")
    }

    @Test func countdownForAPastDateIsNow() {
        #expect(Formatting.countdown(to: now.addingTimeInterval(-5), from: now) == "now")
    }

    @Test func resetsMoreThanADayAwayShowDaysAndHours() {
        let target = now.addingTimeInterval((20 * 24 + 6) * 3600 + 30 * 60)
        #expect(Formatting.countdownClockLabel(for: target, from: now).hasPrefix("20d 6h, "))
    }

    @Test func resetsUnderADayShowCountdownThenClock() {
        let target = now.addingTimeInterval(2 * 3600 + 15 * 60)
        #expect(Formatting.countdownClockLabel(for: target, from: now).hasPrefix("2h 15m, "))
    }
}

extension FormattingTests {
    @Test func absurdlyFarResetsDoNotOverflow() {
        let far = Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(1e20)
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!Formatting.countdown(to: far, from: now).isEmpty)
        #expect(!Formatting.countdownClockLabel(for: far, from: now).isEmpty)
    }
}
