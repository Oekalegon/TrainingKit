import Foundation

/// Smooths a noisy resting-heart-rate reading into a stable value fit to drive
/// ``HeartRateZoneSettings`` updates.
///
/// A single day's resting HR sample swings with sleep quality, illness, alcohol, travel, and watch
/// placement — feeding it straight into the Karvonen zone math would jitter zone boundaries on
/// every re-read. Taking the median over a trailing 1–2 week window absorbs that day-to-day noise
/// while still tracking a genuine fitness change (a lower resting HR that holds for weeks, not a
/// single good night's sleep).
public struct RestingHeartRateSmoother: Sendable {
    /// The trailing window, in days, over which readings are considered — 1–2 weeks of daily
    /// resting HR readings.
    public static let windowInDays = 14

    /// Creates a resting heart rate smoother.
    public init() {}

    /// The median of the given readings, in beats per minute.
    ///
    /// - Parameter readingsBPM: Resting heart rate readings from the trailing window; order
    ///   doesn't matter. Typically one per day, but duplicates/multiple-per-day readings are
    ///   handled the same as any other value — each counts once toward the median.
    /// - Returns: The median reading, or `nil` if `readingsBPM` is empty.
    public func smoothedRestingHeartRateBPM(from readingsBPM: [Double]) -> Double? {
        guard !readingsBPM.isEmpty else { return nil }
        let sorted = readingsBPM.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
}
