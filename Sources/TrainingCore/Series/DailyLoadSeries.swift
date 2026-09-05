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
    public init() {}

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

        let allDays = Set(actualLoadByDay.keys).union(estimatedLoadByDay.keys)
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
        for calculator in calculators {
            if let load = try? calculator.load(for: activity, athlete: athlete) {
                return load.value
            }
        }
        return nil
    }
}
