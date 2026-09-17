import Foundation

/// Merges completed activities and planned activities into one continuous `[DayLoad]`, one entry
/// per calendar day with no gaps, per this merge rule:
///
/// | Day is | Rule |
/// |---|---|
/// | Before `today` | Sum of actual loads. A plan with no matching activity contributes 0. |
/// | `today` | Sum of actual loads if any exist that day, otherwise the planned estimate. |
/// | After `today` | Sum of estimated loads for planned activities. |
///
/// `today` is an injected `Date`, not `Date()`, so the series is deterministic in tests and so a
/// caller can ask "what does the curve look like as of next Monday".
public struct DailyLoadSeries: Sendable {
    /// Creates a daily load series builder.
    public init() {}

    /// Builds the continuous day-by-day merge described above.
    ///
    /// - Parameters:
    ///   - activities: Completed activities to score with `calculators`.
    ///   - plans: Planned activities to score with `estimator`.
    ///   - workouts: The library workouts `plans` reference, looked up by id.
    ///   - estimator: Estimates load for a planned activity's workout.
    ///   - calculators: Tried in order per activity; the first to succeed wins, so an activity
    ///     without heart-rate data can fall back to e.g. ``DurationRPECalculator``.
    ///   - athlete: Supplies the timezone for day boundaries and is passed through to the
    ///     calculators/estimator.
    ///   - today: The boundary between "actual" and "estimated" days; injected rather than
    ///     `Date()` so the series is deterministic.
    /// - Returns: One ``DayLoad`` per calendar day, spanning from the earliest activity/plan (or
    ///   `today`, whichever is earlier) through the latest (or `today`, whichever is later), with
    ///   no gaps.
    public func days(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        estimator: PlannedLoadEstimator,
        calculators: [any LoadCalculator],
        athlete: AthleteProfile,
        today: Date
    ) -> [DayLoad] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone

        let todayStart = calendar.startOfDay(for: today)
        let workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })

        var actualLoadByDay: [Date: Double] = [:]
        for activity in activities {
            guard let load = firstSuccessfulLoad(for: activity, athlete: athlete, calculators: calculators) else {
                continue
            }
            let day = calendar.startOfDay(for: activity.start)
            actualLoadByDay[day, default: 0] += load
        }

        var estimatedLoadByDay: [Date: Double] = [:]
        for plan in plans {
            guard let workout = workoutsByID[plan.workoutID] else { continue }
            let load = plan.expectedLoadOverride ?? estimator.estimatedLoad(for: workout, athlete: athlete).value
            let day = calendar.startOfDay(for: plan.date)
            estimatedLoadByDay[day, default: 0] += load
        }

        // The range always includes `today`, even if the last actual/planned data is days away
        // from it — otherwise a caller who stopped logging activities a while ago would get a
        // series (and downstream CTL/ATL/TSB) that silently stops at the last data point instead
        // of reflecting the detraining between that day and today.
        let allDays = Set(actualLoadByDay.keys).union(estimatedLoadByDay.keys).union([todayStart])
        guard let firstDay = allDays.min(), let lastDay = allDays.max() else { return [] }

        var result: [DayLoad] = []
        var day = firstDay
        while day <= lastDay {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day)! }

            if day < todayStart {
                result.append(DayLoad(day: day, load: actualLoadByDay[day] ?? 0, isProjected: false))
            } else if day == todayStart {
                if let actual = actualLoadByDay[day] {
                    result.append(DayLoad(day: day, load: actual, isProjected: false))
                } else {
                    result.append(DayLoad(day: day, load: estimatedLoadByDay[day] ?? 0, isProjected: true))
                }
            } else {
                result.append(DayLoad(day: day, load: estimatedLoadByDay[day] ?? 0, isProjected: true))
            }
        }
        return result
    }

    private func firstSuccessfulLoad(
        for activity: Activity,
        athlete: AthleteProfile,
        calculators: [any LoadCalculator]
    ) -> Double? {
        var lastError: (any Error)?
        for calculator in calculators {
            do {
                return try calculator.load(for: activity, athlete: athlete).value
            } catch {
                lastError = error
            }
        }
        if let lastError {
            Logging.series.debug(
                "No load calculator produced a value for activity \(activity.id, privacy: .public): \(String(describing: lastError), privacy: .public)"
            )
        }
        return nil
    }
}
