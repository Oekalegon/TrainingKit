import Foundation

/// Computes CTL/ATL/TSB/monotony/strain from a continuous `[DayLoad]` series.
///
/// The EWMA recurrence is sequential by nature (`ctl[d] = ctl[d-1] + (load[d] - ctl[d-1]) / τ`),
/// so no vectorised math is needed here; only the rolling monotony window is worth batching, and
/// even that is a few thousand elements at most for a season of data.
public struct FitnessMetricsCalculator: Sendable {
    /// Creates a fitness metrics calculator.
    public init() {}

    /// Computes the day-by-day fitness metrics for a series.
    ///
    /// - Parameters:
    ///   - series: A continuous, gap-free day sequence, e.g. from ``DailyLoadSeries``.
    ///   - parameters: EWMA time constants and the monotony window length.
    ///   - seed: Starting `(ctl, atl)` as of the day before `series` begins, for a user who only
    ///     imports recent history. Without a seed, the first `ctlTimeConstantDays` days are
    ///     marked ``FitnessMetrics/isWarmingUp``.
    public func metrics(
        for series: [DayLoad],
        parameters: LoadModelParameters,
        seed: (ctl: Double, atl: Double)?
    ) -> [FitnessMetrics] {
        var previousCTL = seed?.ctl ?? 0
        var previousATL = seed?.atl ?? 0
        var loadWindow: [Double] = []
        var result: [FitnessMetrics] = []
        result.reserveCapacity(series.count)

        for (index, dayLoad) in series.enumerated() {
            let load = dayLoad.load
            let ctl = previousCTL + (load - previousCTL) / parameters.ctlTimeConstantDays
            let atl = previousATL + (load - previousATL) / parameters.atlTimeConstantDays
            let tsb = previousCTL - previousATL

            loadWindow.append(load)
            if loadWindow.count > parameters.monotonyWindowDays {
                loadWindow.removeFirst()
            }
            let (monotony, strain) = monotonyAndStrain(window: loadWindow)

            let isWarmingUp = seed == nil && index < Int(parameters.ctlTimeConstantDays)

            result.append(
                FitnessMetrics(
                    day: dayLoad.day,
                    load: load,
                    ctl: ctl,
                    atl: atl,
                    tsb: tsb,
                    monotony: monotony,
                    strain: strain,
                    isProjected: dayLoad.isProjected,
                    isWarmingUp: isWarmingUp
                )
            )

            previousCTL = ctl
            previousATL = atl
        }

        return result
    }

    /// Monotony is mean/stdev (sample standard deviation) over the trailing window; `.nan` when
    /// fewer than 2 days are available or the window has zero variance, per the documented
    /// intent of not clamping a rest week into "monotonous".
    private func monotonyAndStrain(window: [Double]) -> (monotony: Double, strain: Double) {
        guard window.count >= 2 else { return (.nan, .nan) }

        let sum = window.reduce(0, +)
        let mean = sum / Double(window.count)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count - 1)
        let stdev = variance.squareRoot()

        guard stdev != 0 else { return (.nan, .nan) }

        let monotony = mean / stdev
        return (monotony, sum * monotony)
    }
}
