import Foundation

public enum Percentiles {
    /// Percentile `p` (0...100) with linear interpolation between closest ranks; nil when empty.
    public static func value(_ p: Double, of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let clamped = min(100, max(0, p))
        let rank = clamped / 100 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    public static func median(_ values: [Double]) -> Double? {
        value(50, of: values)
    }
}
