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
/// - A plan whose workout isn't in `workouts` can't be described and is left out.
/// - Load uses the same calculators as the app: ``StatisticsCalculator/summary(for:athlete:)`` for
///   completed activities, and the plan's override or the estimator for planned ones. Duration and
///   distance of planned workouts come from ``StatisticsCalculator/projection(for:athlete:)``.
/// - Intensity uses the same classifiers as ``TrainingModel/intensity(of:)-(Activity)``.
public struct CalendarExportBuilder: Sendable {
    /// Computes loads and projections.
    public let statisticsCalculator: StatisticsCalculator
    /// The intensity classifiers' thresholds.
    public let intensityParameters: IntensityClassifierParameters

    /// Creates a builder.
    ///
    /// - Parameters:
    ///   - statisticsCalculator: Computes loads and projections; defaults to the standard one.
    ///   - intensityParameters: The intensity classifiers' thresholds; defaults to the standard ones.
    public init(
        statisticsCalculator: StatisticsCalculator = StatisticsCalculator(),
        intensityParameters: IntensityClassifierParameters = IntensityClassifierParameters()
    ) {
        self.statisticsCalculator = statisticsCalculator
        self.intensityParameters = intensityParameters
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
        let load = summary.load.confidence > 0 ? summary.load : nil
        let intensity: IntensityAssessment?
        if let workout {
            intensity = PlanGuidedIntensityClassifier(parameters: intensityParameters)
                .assess(activity, workout: workout, athlete: athlete)
        } else {
            intensity = PerformedIntensityClassifier(parameters: intensityParameters).assess(activity, athlete: athlete)
        }
        let plannedValues = plan.flatMap { plan in
            workout.map { plannedValues(plan, workout: $0, templateNames: templateNames, athlete: athlete) }
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
            plan: plannedValues
        )
    }

    private func plannedEntry(
        _ plan: PlannedActivity, workout: StructuredWorkout, templateNames: [UUID: String], athlete: AthleteProfile
    ) -> CalendarExport.Entry {
        let expected = plannedValues(plan, workout: workout, templateNames: templateNames, athlete: athlete)
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
            plan: nil
        )
    }

    private func plannedValues(
        _ plan: PlannedActivity, workout: StructuredWorkout, templateNames: [UUID: String], athlete: AthleteProfile
    ) -> CalendarExport.PlannedValues {
        let projection = statisticsCalculator.projection(for: workout, athlete: athlete)
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
