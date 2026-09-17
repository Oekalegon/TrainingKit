import Foundation

/// Computes descriptive statistics from activities, plans, and workouts — pure functions,
/// computed on demand rather than persisted, that share the athlete's activities and zone model
/// with the load pipeline but never feed CTL/ATL.
///
/// A future week is projected from ``PlannedActivity``/``StructuredWorkout`` the same way
/// ``DailyLoadSeries`` projects future days: `today`'s activities win if any exist, otherwise the
/// plan's estimate is used, and every day after `today` is planned-only — an actual ``Activity``
/// dated after `today` is excluded, not just an unmatched plan, so replaying "as of a past date"
/// against a store that already has later data agrees with what ``DailyLoadSeries`` would show.
public struct StatisticsCalculator: Sendable {
    /// Tried in order per activity; the first to succeed wins.
    public var calculators: [any LoadCalculator]
    /// Estimates load for a planned activity's workout.
    public var estimator: any PlannedLoadEstimator
    /// Turns a workout step's `StepGoal` into a duration, for projecting planned distance/time.
    public var durationEstimator: WorkoutDurationEstimator
    /// Gaps between consecutive heart-rate samples longer than this are excluded from time in zone.
    public var gapThresholdSeconds: TimeInterval

    /// Creates a statistics calculator.
    ///
    /// - Parameters:
    ///   - calculators: Tried in order per activity; defaults to an ``ExponentialTRIMPCalculator``
    ///     constructed with the same `gapThresholdSeconds` given here, followed by
    ///     ``DurationRPECalculator``. Passing a custom array is the caller's own choice to decouple
    ///     the two; the default deliberately can't drift out of sync with `gapThresholdSeconds`, so
    ///     that an activity's `load` and its `timeInZone` (below) always agree on which segments
    ///     count as "in the activity".
    ///   - estimator: Estimates load for planned activities; defaults to ``TRIMPPlanEstimator``.
    ///   - durationEstimator: Turns a workout step's goal into a duration; defaults to a plain
    ///     ``WorkoutDurationEstimator``.
    ///   - gapThresholdSeconds: Gaps longer than this are excluded from time in zone (and from the
    ///     default `calculators`' TRIMP integration); defaults to 60.
    public init(
        calculators: [any LoadCalculator]? = nil,
        estimator: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator(),
        gapThresholdSeconds: TimeInterval = 60
    ) {
        self.calculators = calculators ?? [
            ExponentialTRIMPCalculator(gapThresholdSeconds: gapThresholdSeconds),
            DurationRPECalculator(),
        ]
        self.estimator = estimator
        self.durationEstimator = durationEstimator
        self.gapThresholdSeconds = gapThresholdSeconds
    }

    // MARK: - Per activity

    /// Summarizes one completed activity: distance/time/average heart rate, time in zone, and load.
    ///
    /// - Parameters:
    ///   - activity: The activity to summarize.
    ///   - athlete: Supplies the heart-rate zone settings effective on `activity.start` and is
    ///     passed through to `calculators`.
    public func summary(for activity: Activity, athlete: AthleteProfile) -> ActivitySummary {
        Logging.statistics.debug(
            "summary(for:athlete:) activity \(activity.id, privacy: .public) dated \(activity.start, privacy: .public) has \(activity.heartRate.count, privacy: .public) heart-rate samples"
        )
        let load = firstSuccessfulLoad(for: activity, athlete: athlete)
        if load == nil {
            Logging.statistics.warning("summary(for:athlete:) found no successful calculator for activity \(activity.id, privacy: .public); reporting a zero-confidence 0")
        }
        // `.exponentialTRIMP` is picked arbitrarily here — neither method fits "no calculator could
        // score this at all" (LoadMethod has no dedicated case for it). `confidence == 0` is the
        // actual signal; a caller must check it rather than trusting `.method` alone in this case.
        return ActivitySummary(
            activityID: activity.id,
            sport: activity.sport,
            distanceMeters: activity.distanceMeters,
            movingTime: activity.duration,
            averageHeartRateBPM: averageHeartRate(activity.heartRate),
            timeInZone: timeInZone(for: activity, athlete: athlete),
            load: load ?? TrainingLoad(value: 0, method: .exponentialTRIMP, confidence: 0)
        )
    }

    // MARK: - Per week

    /// Computes one ``WeeklyStats`` per calendar week from the earliest activity/plan (or `today`,
    /// whichever is earlier) through `today` (or the latest activity/plan, whichever is later).
    ///
    /// Week boundaries follow ``AthleteProfile/weekStartsOn`` in ``AthleteProfile/timeZone``.
    ///
    /// - Parameters:
    ///   - activities: Completed activities to summarize with `calculators`.
    ///   - plans: Planned activities to project with `estimator`/`durationEstimator` for weeks that
    ///     aren't fully in the past.
    ///   - workouts: The library workouts `plans` reference, looked up by id.
    ///   - athlete: Supplies the timezone, week-start day, and zone settings used throughout.
    ///   - today: The boundary between "actual" and "estimated" days; injected rather than
    ///     `Date()` so the result is deterministic.
    /// - Returns: One ``WeeklyStats`` per calendar week, oldest first, with no gaps.
    public func weeklyStats(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        athlete: AthleteProfile,
        asOf today: Date
    ) -> [WeeklyStats] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        calendar.firstWeekday = athlete.weekStartsOn.rawValue

        let allDays = activities.map(\.start) + plans.map(\.date) + [today]
        guard let firstDay = allDays.min(), let lastDay = allDays.max() else { return [] }

        let firstWeekStart = weekStart(containing: firstDay, calendar: calendar)
        let lastWeekStart = weekStart(containing: lastDay, calendar: calendar)

        var result: [WeeklyStats] = []
        var previous: PeriodStats?
        var weekStartDate = firstWeekStart
        while weekStartDate <= lastWeekStart {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStartDate)!
            let period = periodStats(
                activities: activities,
                plans: plans,
                workouts: workouts,
                athlete: athlete,
                range: weekStartDate...weekEnd,
                asOf: today,
                previous: previous
            )
            result.append(WeeklyStats(weekStart: weekStartDate, period: period))
            previous = period
            weekStartDate = calendar.date(byAdding: .day, value: 7, to: weekStartDate)!
        }
        return result
    }

    // MARK: - Per period

    /// Computes descriptive totals over an arbitrary calendar-day `range`.
    ///
    /// - Parameters:
    ///   - activities: Completed activities to summarize with `calculators`.
    ///   - plans: Planned activities to project with `estimator`/`durationEstimator` for days in
    ///     `range` that aren't in the past.
    ///   - workouts: The library workouts `plans` reference, looked up by id.
    ///   - athlete: Supplies the timezone and zone settings used throughout.
    ///   - range: The calendar-day range to summarize, in the athlete's timezone. Both bounds are
    ///     inclusive whole days.
    ///   - today: The boundary between "actual" and "estimated" days, matching ``DailyLoadSeries``.
    ///   - previous: The immediately preceding period of the same length, to compute `delta`
    ///     against; `nil` if there isn't one (e.g. the first week in a series).
    public func periodStats(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        athlete: AthleteProfile,
        range: ClosedRange<Date>,
        asOf today: Date,
        previous: PeriodStats?
    ) -> PeriodStats {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let todayStart = calendar.startOfDay(for: today)
        let rangeStart = calendar.startOfDay(for: range.lowerBound)
        let rangeEnd = calendar.startOfDay(for: range.upperBound)
        let workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })

        // Mirrors DailyLoadSeries's merge rule exactly: a day after today is planned-only, so an
        // actual activity dated after `today` (e.g. replaying "as of last Tuesday" against data
        // that already includes what happened since) is excluded here just as DailyLoadSeries
        // ignores it for CTL/ATL, rather than this descriptive view silently disagreeing with the
        // fitness series about what "today" means for the same data.
        let activitiesInRange = activities.filter { activity in
            let day = calendar.startOfDay(for: activity.start)
            return day >= rangeStart && day <= rangeEnd && day <= todayStart
        }
        let daysWithActivity = Set(activitiesInRange.map { calendar.startOfDay(for: $0.start) })

        // Mirrors DailyLoadSeries's merge rule: a plan only contributes on today (if nothing
        // actual happened that day) or on a day after today.
        let plansInRange = plans.filter { plan in
            let day = calendar.startOfDay(for: plan.date)
            guard day >= rangeStart && day <= rangeEnd else { return false }
            if day < todayStart { return false }
            if day == todayStart { return !daysWithActivity.contains(day) }
            return true
        }

        var itemsBySport: [Sport: [StatItem]] = [:]
        for activity in activitiesInRange {
            let summary = summary(for: activity, athlete: athlete)
            let item = StatItem(
                distanceMeters: summary.distanceMeters,
                time: summary.movingTime,
                load: summary.load.value,
                timeInZone: summary.timeInZone
            )
            itemsBySport[activity.sport, default: []].append(item)
        }
        for plan in plansInRange {
            guard let workout = workoutsByID[plan.workoutID] else { continue }
            let projection = project(workout: workout, athlete: athlete)
            let load = plan.expectedLoadOverride ?? estimator.estimatedLoad(for: workout, athlete: athlete).value
            let item = StatItem(
                distanceMeters: projection.distanceMeters,
                time: projection.duration,
                load: load,
                timeInZone: projection.timeInZone
            )
            itemsBySport[workout.sport, default: []].append(item)
        }

        let isProjected = rangeEnd > todayStart || (rangeEnd == todayStart && !plansInRange.isEmpty)

        var bySport: [Sport: SportPeriodStats] = [:]
        for (sport, items) in itemsBySport {
            bySport[sport] = SportPeriodStats(
                sport: sport,
                distanceMeters: items.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
                time: items.reduce(0) { $0 + $1.time },
                load: items.reduce(0) { $0 + $1.load },
                timeInZone: items.reduce(TimeInZone()) { $0 + $1.timeInZone },
                activityCount: items.count
            )
        }

        let allItems = itemsBySport.values.flatMap { $0 }
        let longest = allItems.max { $0.time < $1.time }

        let current = PeriodStats(
            range: range,
            isProjected: isProjected,
            bySport: bySport,
            totalDistanceMeters: allItems.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            totalTime: allItems.reduce(0) { $0 + $1.time },
            totalLoad: allItems.reduce(0) { $0 + $1.load },
            timeInZone: allItems.reduce(TimeInZone()) { $0 + $1.timeInZone },
            activityCount: allItems.count,
            longestActivityTime: longest?.time ?? 0,
            longestActivityDistanceMeters: longest?.distanceMeters,
            delta: nil
        )

        guard let previous else { return current }
        return PeriodStats(
            range: current.range,
            isProjected: current.isProjected,
            bySport: current.bySport,
            totalDistanceMeters: current.totalDistanceMeters,
            totalTime: current.totalTime,
            totalLoad: current.totalLoad,
            timeInZone: current.timeInZone,
            activityCount: current.activityCount,
            longestActivityTime: current.longestActivityTime,
            longestActivityDistanceMeters: current.longestActivityDistanceMeters,
            delta: PeriodDelta.delta(from: previous, to: current)
        )
    }

    // MARK: - Support

    /// One contributing activity or planned activity's totals, before grouping by sport.
    private struct StatItem {
        let distanceMeters: Double?
        let time: TimeInterval
        let load: Double
        let timeInZone: TimeInZone
    }

    /// An unweighted mean of every sample's bpm. This skews toward whichever effort level happens
    /// to be sampled more densely on an irregularly-sampled stream (unlike `load`/`timeInZone`,
    /// which are time-weighted via ``HeartRateSegmentIterator``) — acceptable here since this is a
    /// display-only descriptive stat that never feeds load, but worth revisiting if it starts
    /// informing anything load-adjacent.
    private func averageHeartRate(_ samples: [HeartRateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.bpm } / Double(samples.count)
    }

    private func firstSuccessfulLoad(for activity: Activity, athlete: AthleteProfile) -> TrainingLoad? {
        var lastError: (any Error)?
        for calculator in calculators {
            do {
                return try calculator.load(for: activity, athlete: athlete)
            } catch {
                lastError = error
            }
        }
        if let lastError {
            Logging.statistics.debug(
                "No load calculator produced a value for activity \(activity.id, privacy: .public): \(String(describing: lastError), privacy: .public)"
            )
        }
        return nil
    }

    /// Integrates ``Activity/heartRate`` into per-zone seconds via ``TimeInZoneBuilder``, sharing
    /// segments and the gap rule with ``ExponentialTRIMPCalculator``.
    private func timeInZone(for activity: Activity, athlete: AthleteProfile) -> TimeInZone {
        TimeInZoneBuilder(gapThresholdSeconds: gapThresholdSeconds).timeInZone(for: activity, athlete: athlete)
    }

    /// The projected distance/duration/time-in-zone for a planned workout, via
    /// ``PlannedWorkoutProjector``.
    private func project(workout: StructuredWorkout, athlete: AthleteProfile) -> PlannedWorkoutProjector.Projection {
        PlannedWorkoutProjector(durationEstimator: durationEstimator).project(workout: workout, athlete: athlete)
    }

    private func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)!
    }
}
