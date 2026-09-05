import Foundation

/// One day's fitness metrics, produced by ``FitnessMetricsCalculator``.
public struct FitnessMetrics: Sendable, Hashable {
    public let day: Date
    public let load: Double
    /// 42-day (by default) exponentially weighted moving average of load — chronic training load.
    public let ctl: Double
    /// 7-day (by default) exponentially weighted moving average of load — acute training load.
    public let atl: Double
    /// Yesterday's CTL minus yesterday's ATL — training stress balance.
    public let tsb: Double
    /// Mean divided by standard deviation of the trailing window. `.nan` when the window's
    /// standard deviation is 0 (a perfectly flat week, including a week of full rest) — this is
    /// intentionally not clamped, since a rest week isn't "monotonous" in the sense the metric
    /// is meant to flag.
    public let monotony: Double
    /// Trailing-window load sum multiplied by `monotony`.
    public let strain: Double
    public let isProjected: Bool
    /// `true` while there isn't yet a full CTL time constant's worth of history feeding the
    /// series (unless a seed was supplied to ``FitnessMetricsCalculator``), during which CTL/ATL
    /// are still ramping up from zero and shouldn't be trusted.
    public let isWarmingUp: Bool

    public init(
        day: Date,
        load: Double,
        ctl: Double,
        atl: Double,
        tsb: Double,
        monotony: Double,
        strain: Double,
        isProjected: Bool,
        isWarmingUp: Bool
    ) {
        self.day = day
        self.load = load
        self.ctl = ctl
        self.atl = atl
        self.tsb = tsb
        self.monotony = monotony
        self.strain = strain
        self.isProjected = isProjected
        self.isWarmingUp = isWarmingUp
    }
}
