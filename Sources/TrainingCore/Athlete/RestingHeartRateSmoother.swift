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

    /// The start of the trailing window ending at (and including) `date` — `date` minus
    /// ``windowInDays`` days.
    ///
    /// A pure, testable seam for the date arithmetic a HealthKit query predicate needs, kept out of
    /// the adapter that builds that predicate.
    ///
    /// - Parameter date: The end of the window (typically "today").
    /// - Returns: The window's start date.
    public func windowStart(endingAt date: Date) -> Date {
        date.addingTimeInterval(-Double(Self.windowInDays) * 86400)
    }

    /// The median of the given readings, one per calendar day.
    ///
    /// Multiple readings on the same day (e.g. a watch and a paired phone each recording their own
    /// resting HR, or a same-day correction) are averaged into a single daily value first, so a day
    /// with several samples doesn't outweigh a day with one in the median — each *day*, not each
    /// sample, gets one vote.
    ///
    /// - Parameters:
    ///   - readings: Resting heart rate readings from the trailing window, each with the date it
    ///     was recorded on; order doesn't matter.
    ///   - calendar: The calendar used to group readings by day; defaults to `.current`.
    /// - Returns: The median of the per-day averages, or `nil` if `readings` is empty.
    public func smoothedRestingHeartRateBPM(
        from readings: [(date: Date, bpm: Double)],
        calendar: Calendar = .current
    ) -> Double? {
        guard !readings.isEmpty else { return nil }
        let perDay = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }
        let dailyAveragesBPM = perDay.values.map { dayReadings in
            dayReadings.map(\.bpm).reduce(0, +) / Double(dayReadings.count)
        }
        return smoothedRestingHeartRateBPM(from: dailyAveragesBPM)
    }

    /// The median of the given readings.
    ///
    /// - Parameter readingsBPM: Already one-per-day resting heart rate readings; order doesn't
    ///   matter. Prefer ``smoothedRestingHeartRateBPM(from:calendar:)`` when readings carry dates
    ///   and may include more than one per day.
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
