import Foundation

/// The change in a period's totals versus the previous period of the same length.
///
/// Every `*Fraction` is 0 when the previous period's corresponding total was 0, rather than
/// `.infinity`/`.nan` — there's no meaningful percentage change from zero.
public struct PeriodDelta: Sendable, Hashable {
    /// Absolute change in total distance, in meters.
    public let distanceMeters: Double
    /// Relative change in total distance, e.g. `0.12` for +12%.
    public let distanceFraction: Double
    /// Absolute change in total time.
    public let time: TimeInterval
    /// Relative change in total time.
    public let timeFraction: Double
    /// Absolute change in total load.
    public let load: Double
    /// Relative change in total load.
    public let loadFraction: Double

    /// Creates a period delta.
    public init(
        distanceMeters: Double,
        distanceFraction: Double,
        time: TimeInterval,
        timeFraction: Double,
        load: Double,
        loadFraction: Double
    ) {
        self.distanceMeters = distanceMeters
        self.distanceFraction = distanceFraction
        self.time = time
        self.timeFraction = timeFraction
        self.load = load
        self.loadFraction = loadFraction
    }

    /// The delta of `current` versus `previous`, guarding every fraction against a zero
    /// denominator.
    static func delta(from previous: PeriodStats, to current: PeriodStats) -> PeriodDelta {
        PeriodDelta(
            distanceMeters: current.totalDistanceMeters - previous.totalDistanceMeters,
            distanceFraction: fraction(current.totalDistanceMeters - previous.totalDistanceMeters, of: previous.totalDistanceMeters),
            time: current.totalTime - previous.totalTime,
            timeFraction: fraction(current.totalTime - previous.totalTime, of: previous.totalTime),
            load: current.totalLoad - previous.totalLoad,
            loadFraction: fraction(current.totalLoad - previous.totalLoad, of: previous.totalLoad)
        )
    }

    private static func fraction(_ delta: Double, of previousTotal: Double) -> Double {
        guard previousTotal != 0 else { return 0 }
        return delta / previousTotal
    }
}

/// A ``PeriodDelta`` comparing a calendar week against the previous one; kept as a distinct name
/// for readability at ``WeeklyStats/delta``, since a ``PeriodDelta`` is the same shape regardless
/// of period length.
public typealias WeeklyDelta = PeriodDelta
