import Foundation

/// Assembles a ``CalendarExport`` from already-fetched activities, plans, workouts and metrics.
///
/// Pure, so it can be tested without stores. ``TrainingModel/calendarExport(from:through:templates:asOf:)``
/// does the fetching and metrics computation, then calls this.
///
/// The rules, matching what the app shows:
/// - A completed activity is always included. If it fulfilled a plan (that plan's
///   `completedActivityID` is the activity), the plan's expected values ride along in
///   ``CalendarExport/Entry/plan`` and the plan gets no entry of its own.
/// - An unfulfilled plan is included only if it's for today or later. One from before today is
///   missed and left out, like the week view's missed-plan outline, which carries no load.
/// - A plan whose workout isn't in `workouts` can't be described and is left out. A completed
///   activity that fulfilled such a plan is still included, just without `name`, `template` or `plan`.
/// - Only activities in `activities` can fulfil a plan: one just outside the period (e.g. a run
///   after midnight that fulfilled the last day's plan) doesn't, so that plan is treated as
///   unfulfilled, and left out as missed if it's before today.
/// - Load uses the same calculators as the app: ``StatisticsCalculator/summary(for:athlete:)`` for
///   completed activities, and the plan's override or the estimator for planned ones. Duration and
///   distance of planned workouts come from
///   ``StatisticsCalculator/projection(for:athlete:paceHistory:before:excluding:)`` with
///   ``paceHistory``, so they match what the app shows (MVP2-35).
/// - Intensity uses the same classifiers as ``TrainingModel/intensity(of:)-(Activity)``.
public struct CalendarExportBuilder: Sendable {
    /// Computes loads and projections.
    public let statisticsCalculator: StatisticsCalculator
    /// The intensity classifiers' thresholds.
    public let intensityParameters: IntensityClassifierParameters
    /// Earlier activities planned workouts' duration and distance are forecast from; empty for
    /// the pace model alone.
    public let paceHistory: PaceHistory

    /// Creates a builder.
    ///
    /// - Parameters:
    ///   - statisticsCalculator: Computes loads and projections; defaults to the standard one.
    ///   - intensityParameters: The intensity classifiers' thresholds; defaults to the standard ones.
    ///   - paceHistory: Earlier activities to forecast planned workouts from; defaults to none.
    public init(
        statisticsCalculator: StatisticsCalculator = StatisticsCalculator(),
        intensityParameters: IntensityClassifierParameters = IntensityClassifierParameters(),
        paceHistory: PaceHistory = .empty
    ) {
        self.statisticsCalculator = statisticsCalculator
        self.intensityParameters = intensityParameters
        self.paceHistory = paceHistory
    }

    /// Builds the export for every calendar day from `firstDay` through `lastDay`.
    ///
    /// - Parameters:
    ///   - firstDay: Any time on the first day of the period, in `athlete`'s time zone.
    ///   - lastDay: Any time on the last day, inclusive. Swapped with `firstDay` if earlier.
    ///   - activities: Completed activities; those outside the period are ignored.
    ///   - plans: Planned activities; those outside the period are ignored.
    ///   - workouts: The workouts the plans refer to.
    ///   - templates: Templates, to name the one each workout was built from.
    ///   - metrics: Fitness metrics; days without an entry get `nil` metrics.
    ///   - athlete: Supplies the time zone, zones and pace model.
    ///   - today: Plans before this day that weren't performed are missed and left out.
    ///   - generatedAt: Stamped into the export.
    /// - Returns: The export.
    public func build(
        from firstDay: Date,
        through lastDay: Date,
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        templates: [WorkoutTemplate],
        metrics: [FitnessMetrics],
        athlete: AthleteProfile,
        today: Date,
        generatedAt: Date
    ) -> CalendarExport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let (start, end) = (min(firstDay, lastDay), max(firstDay, lastDay))
        let firstStart = calendar.startOfDay(for: start)
        let lastStart = calendar.startOfDay(for: end)
        let todayStart = calendar.startOfDay(for: today)

        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let templateNames = Dictionary(templates.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let activitiesByDay = Dictionary(grouping: activities) { calendar.startOfDay(for: $0.start) }
        let plansByDay = Dictionary(grouping: plans) { calendar.startOfDay(for: $0.date) }
        let metricsByDay = Dictionary(metrics.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { _, last in last })
        let planByActivity = Dictionary(
            plans.compactMap { plan in plan.completedActivityID.map { ($0, plan) } },
            uniquingKeysWith: { first, _ in first }
        )
        let activityIDs = Set(activities.map(\.id))

        var days: [CalendarExport.Day] = []
        var day = firstStart
        while day <= lastStart {
            // Cancelled mid-build: stop early. The caller discards the partial result.
            if Task.isCancelled { break }
            let completed = (activitiesByDay[day] ?? [])
                .sorted { $0.start < $1.start }
                .map { activity -> CalendarExport.Entry in
                    let plan = planByActivity[activity.id]
                    let planWorkout = plan.flatMap { workoutsByID[$0.workoutID] }
                    return completedEntry(
                        activity, plan: plan, workout: planWorkout, templateNames: templateNames, athlete: athlete
                    )
                }
            let planned = (plansByDay[day] ?? [])
                .filter { plan in
                    // Fulfilled: shown with its activity. Missed: left out.
                    let fulfilled = plan.completedActivityID.map(activityIDs.contains) ?? false
                    return !fulfilled && day >= todayStart
                }
                .compactMap { plan -> CalendarExport.Entry? in
                    guard let workout = workoutsByID[plan.workoutID] else { return nil }
                    return plannedEntry(plan, workout: workout, templateNames: templateNames, athlete: athlete)
                }
            days.append(CalendarExport.Day(
                date: Self.dayString(day, calendar: calendar),
                metrics: metricsByDay[day].map(Self.metrics),
                activities: completed + planned
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return CalendarExport(
            schemaVersion: CalendarExport.currentSchemaVersion,
            generatedAt: generatedAt,
            timeZone: athlete.timeZone.identifier,
            firstDay: Self.dayString(firstStart, calendar: calendar),
            lastDay: Self.dayString(lastStart, calendar: calendar),
            days: days
        )
    }

    private func completedEntry(
        _ activity: Activity, plan: PlannedActivity?, workout: StructuredWorkout?,
        templateNames: [UUID: String], athlete: AthleteProfile
    ) -> CalendarExport.Entry {
        let summary = statisticsCalculator.summary(for: activity, athlete: athlete)
        // No load when no calculator could score it, and when a heart-rate recording produced
        // exactly zero: that is a recording with no usable segments (sparse samples, or no zone
        // settings in effect yet), not a measured nothing, so it isn't labelled `heartRate`.
        let scored = summary.load.confidence > 0 ? summary.load : nil
        let load = scored.flatMap { $0.method == .exponentialTRIMP && $0.value == 0 ? nil : $0 }
        let intensity: IntensityAssessment?
        if let workout {
            intensity = PlanGuidedIntensityClassifier(parameters: intensityParameters)
                .assess(activity, workout: workout, athlete: athlete)
        } else {
            intensity = PerformedIntensityClassifier(parameters: intensityParameters).assess(activity, athlete: athlete)
        }
        let expected = plan.flatMap { plan in
            workout.map {
                plannedValues(
                    plan, workout: $0, templateNames: templateNames, athlete: athlete,
                    before: activity.start, excluding: activity.id
                )
            }
        }
        return CalendarExport.Entry(
            status: .completed,
            start: activity.start,
            name: workout?.name,
            sport: Self.sportIdentifier(activity.sport),
            template: workout?.templateID.flatMap { templateNames[$0] },
            intensity: intensity.map { Self.intensityIdentifier($0.category) },
            trimp: load.map { Self.finite($0.value) } ?? nil,
            trimpSource: load.map { Self.trimpSource(for: $0.method) },
            durationSeconds: activity.duration,
            distanceMeters: activity.distanceMeters,
            plan: expected,
            steps: workout.map { steps(of: $0, athlete: athlete, before: activity.start, excluding: activity.id) } ?? []
        )
    }

    private func plannedEntry(
        _ plan: PlannedActivity, workout: StructuredWorkout, templateNames: [UUID: String], athlete: AthleteProfile
    ) -> CalendarExport.Entry {
        let expected = plannedValues(
            plan, workout: workout, templateNames: templateNames, athlete: athlete, before: plan.date, excluding: nil
        )
        let intensity = PlannedIntensityClassifier(parameters: intensityParameters).assess(workout, athlete: athlete)
        return CalendarExport.Entry(
            status: .planned,
            start: nil,
            name: workout.name,
            sport: Self.sportIdentifier(workout.sport),
            template: expected.template,
            intensity: Self.intensityIdentifier(intensity.category),
            trimp: expected.trimp,
            trimpSource: expected.trimpSource,
            durationSeconds: expected.durationSeconds,
            distanceMeters: expected.distanceMeters,
            plan: nil,
            steps: steps(of: workout, athlete: athlete, before: plan.date, excluding: nil)
        )
    }

    /// `workout`'s steps as forecast from ``paceHistory``, using only activities before `cutoff` and
    /// never `excludedActivityID` (the plan's own activity).
    private func steps(
        of workout: StructuredWorkout, athlete: AthleteProfile, before cutoff: Date, excluding excludedActivityID: UUID?
    ) -> [CalendarExport.Step] {
        statisticsCalculator.stepProjections(
            for: workout, athlete: athlete, paceHistory: paceHistory, before: cutoff, excluding: excludedActivityID
        ).map { projection in
            let goal: String
            switch projection.step.goal {
            case .time: goal = "time"
            case .distance: goal = "distance"
            case .open: goal = "open"
            }
            return CalendarExport.Step(
                kind: Self.stepKindIdentifier(projection.step.kind),
                block: projection.block,
                repetition: projection.repetition,
                goal: goal,
                durationSeconds: Self.finite(projection.duration) ?? 0,
                distanceMeters: projection.distanceMeters.flatMap(Self.finite),
                target: projection.step.target.map(Self.target)
            )
        }
    }

    private static func stepKindIdentifier(_ kind: StepKind) -> String {
        switch kind {
        case .warmup: "warmup"
        case .work: "work"
        case .recovery: "recovery"
        case .cooldown: "cooldown"
        }
    }

    private static func target(_ target: IntensityTarget) -> CalendarExport.Target {
        switch target {
        case .heartRateZone(let zone):
            CalendarExport.Target(type: "heartRateZone", zone: zone, rpe: nil, min: nil, max: nil)
        case .heartRateRange(let low, let high):
            CalendarExport.Target(type: "heartRateRange", zone: nil, rpe: nil, min: finite(low), max: finite(high))
        case .pace(let range):
            CalendarExport.Target(type: "pace", zone: nil, rpe: nil, min: finite(range.lowerBound), max: finite(range.upperBound))
        case .power(let range):
            CalendarExport.Target(type: "power", zone: nil, rpe: nil, min: finite(range.lowerBound), max: finite(range.upperBound))
        case .rpe(let value):
            CalendarExport.Target(type: "rpe", zone: nil, rpe: value, min: nil, max: nil)
        }
    }

    private func plannedValues(
        _ plan: PlannedActivity, workout: StructuredWorkout, templateNames: [UUID: String], athlete: AthleteProfile,
        before cutoff: Date, excluding excludedActivityID: UUID?
    ) -> CalendarExport.PlannedValues {
        let projection = statisticsCalculator.projection(
            for: workout, athlete: athlete, paceHistory: paceHistory, before: cutoff, excluding: excludedActivityID
        )
        let trimp: Double
        let source: CalendarExport.Entry.TRIMPSource
        if let override = plan.expectedLoadOverride {
            (trimp, source) = (override, .override)
        } else {
            (trimp, source) = (statisticsCalculator.estimator.estimatedLoad(for: workout, athlete: athlete).value, .estimated)
        }
        return CalendarExport.PlannedValues(
            name: workout.name,
            template: workout.templateID.flatMap { templateNames[$0] },
            trimp: Self.finite(trimp) ?? 0,
            trimpSource: source,
            durationSeconds: projection.duration,
            distanceMeters: projection.distanceMeters.flatMap(Self.finite)
        )
    }

    private static func metrics(_ metrics: FitnessMetrics) -> CalendarExport.Metrics {
        CalendarExport.Metrics(
            load: finite(metrics.load) ?? 0,
            ctl: finite(metrics.ctl) ?? 0,
            atl: finite(metrics.atl) ?? 0,
            tsb: finite(metrics.tsb) ?? 0,
            monotony: finite(metrics.monotony),
            strain: finite(metrics.strain),
            isProjected: metrics.isProjected,
            isWarmingUp: metrics.isWarmingUp
        )
    }

    /// `value`, or `nil` when it's NaN or infinite (JSON can't represent either).
    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    static func dayString(_ day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func sportIdentifier(_ sport: Sport) -> String {
        switch sport {
        case .running: "running"
        case .indoorRunning: "indoorRunning"
        case .outdoorRunning: "outdoorRunning"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .strength: "strength"
        case .coreStrengthTraining: "coreStrengthTraining"
        case .walking: "walking"
        case .rowing: "rowing"
        case .hiking: "hiking"
        case .other(let name): name
        }
    }

    /// The sport written as `identifier` by ``sportIdentifier(_:)``; an unknown one is its own label.
    static func sport(identifier: String) -> Sport {
        switch identifier {
        case "running": .running
        case "indoorRunning": .indoorRunning
        case "outdoorRunning": .outdoorRunning
        case "cycling": .cycling
        case "swimming": .swimming
        case "strength": .strength
        case "coreStrengthTraining": .coreStrengthTraining
        case "walking": .walking
        case "rowing": .rowing
        case "hiking": .hiking
        default: .other(identifier)
        }
    }

    static func intensityIdentifier(_ category: IntensityCategory) -> String {
        switch category {
        case .veryLow: "veryLow"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }

    static func trimpSource(for method: LoadMethod) -> CalendarExport.Entry.TRIMPSource {
        switch method {
        case .exponentialTRIMP: .heartRate
        case .durationRPE: .perceivedExertion
        case .estimatedFromPlan: .estimated
        case .manual: .manual
        }
    }
}
