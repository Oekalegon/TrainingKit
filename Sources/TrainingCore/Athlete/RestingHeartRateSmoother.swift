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

    /// The percentile of each day's heart rate that stands for that day's resting heart rate.
    ///
    /// The 5th percentile sits just above the sleeping low, close to the morning pulse the
    /// Karvonen method is built around, and is robust against single artefact samples that a plain
    /// minimum would pick up.
    public static let dailyRestingPercentile = 0.05

    /// The fewest samples a day needs to count; a sparsely worn day would otherwise yield a
    /// "low" that is really just one active moment.
    public static let minimumSamplesPerDay = 20

    /// The most the derived resting heart rate may sit above the sleeping minimum, in bpm.
    ///
    /// A sanity check: the true resting rate is only a few bpm above the sleeping low, so a derived
    /// value much further above it means the low percentile was contaminated (a watch worn only
    /// while active, say) and would overstate the resting rate and shrink the heart rate reserve.
    public static let maximumAboveSleepingMinimumBPM = 10.0

    /// The resting heart rate derived from ordinary heart rate samples rather than a precomputed
    /// resting value: the low percentile of each day's samples, then the median over those days,
    /// capped at ``maximumAboveSleepingMinimumBPM`` above the sleeping minimum.
    ///
    /// The sleeping minimum is the median over the days of each day's lowest sample. Using the median
    /// rather than the overall lowest sample stops a single artefact from pulling the cap down.
    ///
    /// - Parameters:
    ///   - samples: Heart rate samples from the trailing window, with the time each was recorded;
    ///     order doesn't matter.
    ///   - calendar: The calendar used to group samples by day; defaults to `.current`.
    /// - Returns: The capped resting heart rate over the days that have at least
    ///   ``minimumSamplesPerDay`` samples, or `nil` if no day qualifies.
    public func restingHeartRateBPM(
        fromHeartRateSamples samples: [(date: Date, bpm: Double)],
        calendar: Calendar = .current
    ) -> Double? {
        let perDay = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
        let qualifyingDays = perDay.values.filter { $0.count >= Self.minimumSamplesPerDay }.map { $0.map(\.bpm) }
        let dailyLows = qualifyingDays.map { Self.percentile(Self.dailyRestingPercentile, of: $0) }
        guard let resting = smoothedRestingHeartRateBPM(from: dailyLows),
              let sleepingMinimum = smoothedRestingHeartRateBPM(from: qualifyingDays.compactMap { $0.min() })
        else { return nil }
        return min(resting, sleepingMinimum + Self.maximumAboveSleepingMinimumBPM)
    }

    /// The linearly interpolated percentile (`fraction` in 0...1) of `values`, which must not be empty.
    static func percentile(_ fraction: Double, of values: [Double]) -> Double {
        let sorted = values.sorted()
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
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
