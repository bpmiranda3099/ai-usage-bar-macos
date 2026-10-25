import Foundation

/// Percent values shown in meters: whole numbers clamped to 0...100.
enum Percent {
    static func clamped(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    /// 0.5 -> 50. Out-of-range fractions are clamped.
    static func fromFraction(_ fraction: Double) -> Int {
        clamped(Int((fraction * 100).rounded()))
    }

    /// Percent of `limit` still available after `used`; 0 when the limit is not positive.
    static func remaining(used: Double, limit: Double) -> Int {
        guard limit > 0 else { return 0 }
        return fromFraction(1 - used / limit)
    }
}
