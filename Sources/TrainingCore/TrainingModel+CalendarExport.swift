import Foundation

/// Exporting a period of the training calendar as JSON (MVP2-100).
extension TrainingModel {
    /// How many CTL time constants of history before the period are read to warm up the series.
    /// After six, history older than that contributes under 0.25% of CTL, so the exported CTL and
    /// ATL match the app's (which is seeded from the full history) to well within rounding.
    static let calendarExportWarmUpTimeConstants = 6.0

    /// A day-by-day ``CalendarExport`` of every calendar day from `firstDay` through `lastDay`.
    ///
    /// Reads activities, plans and workouts straight from the stores, so ``activities``,
    /// ``plans`` and ``metrics`` are left as they are and the period can be any length, past or
    /// future. Metrics are computed fresh over the period plus a warm-up of
    /// `6 × ctlTimeConstantDays` (about eight months by default) before it, so CTL and ATL don't
    /// start cold at the period's first day. Days after the last activity or plan get zero-load
    /// projected metrics, as in the app's charts.
    ///
    /// The warm-up means about eight months of activities, with their heart-rate samples, are read
    /// and scored on every call, however short the period: the price of metrics that don't depend
    /// on the app's cache. A season can take a few hundred milliseconds on a phone.
    ///
    /// Planned durations and distances are forecast from ``paceHistory`` as last refreshed (see
    /// ``refreshPaceHistory(in:gapThresholdSeconds:)``), so they match the app's cards.
    ///
    /// See ``CalendarExportBuilder`` for which activities and plans are included.
    ///
    /// - Parameters:
    ///   - firstDay: Any time on the first day of the period, in the athlete's time zone.
    ///   - lastDay: Any time on the last day, inclusive.
    ///   - templates: Templates to name each planned workout's template; defaults to the built-in
    ///     library.
    ///   - today: Separates actual from expected load, and missed plans from upcoming ones.
    /// - Returns: The export, ready to encode with ``CalendarExport/jsonData()``.
    /// - Throws: Whatever the stores throw, or `CancellationError` if the calling task is cancelled.
    public func calendarExport(
        from firstDay: Date,
        through lastDay: Date,
        templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all,
        asOf today: Date = .now
    ) async throws -> CalendarExport {
        // Read once: the stores are awaited below, and an athlete or parameter change landing in
        // between must not leave the metrics and the builder working from different ones.
        let athlete = self.athlete
        let parameters = self.parameters
        try Task.checkCancellation()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let periodStart = calendar.startOfDay(for: min(firstDay, lastDay))
        let periodEndDay = calendar.startOfDay(for: max(firstDay, lastDay))
        let periodEnd = calendar.date(byAdding: .day, value: 1, to: periodEndDay)?.addingTimeInterval(-1) ?? periodEndDay
        let warmUpDays = Int((parameters.ctlTimeConstantDays * Self.calendarExportWarmUpTimeConstants).rounded(.up))
        let warmUpStart = calendar.date(byAdding: .day, value: -warmUpDays, to: periodStart) ?? periodStart

        let fetchRange = warmUpStart...periodEnd
        let fetchedActivities = try await stores.activityStore.activities(in: fetchRange)
        let fetchedPlans = try await stores.planStore.plans(in: fetchRange)
        let fetchedWorkouts = try await stores.workoutStore.workouts()

        let metrics = await Self.buildMetricsWithoutCache(
            activities: fetchedActivities,
            plans: fetchedPlans,
            publishRange: periodStart...periodEnd,
            workouts: fetchedWorkouts,
            estimator: estimator,
            calculators: calculators,
            athlete: athlete,
            parameters: parameters,
            today: today
        )

        // The builder computes TRIMP, time in zone and intensity for every activity, walking all of
        // their heart-rate samples: a season can take a few hundred milliseconds on a phone. It and
        // its inputs are Sendable, so it runs off the main actor rather than freezing the UI.
        let period = periodStart...periodEnd
        let builder = CalendarExportBuilder(intensityParameters: intensityParameters, paceHistory: paceHistory)
        let periodActivities = fetchedActivities.filter { period.contains($0.start) }
        let periodPlans = fetchedPlans.filter { period.contains($0.date) }
        let periodMetrics = metrics.filter { period.contains($0.day) }
        // `Task.detached` doesn't inherit the caller's cancellation, so forward it: dismissing the
        // share sheet mid-export stops the build instead of finishing a result nobody will read.
        let build = Task.detached(priority: .userInitiated) {
            builder.build(
                from: periodStart,
                through: periodEndDay,
                activities: periodActivities,
                plans: periodPlans,
                workouts: fetchedWorkouts,
                templates: templates,
                metrics: periodMetrics,
                athlete: athlete,
                today: today,
                generatedAt: today
            )
        }
        let export = await withTaskCancellationHandler { await build.value } onCancel: { build.cancel() }
        try Task.checkCancellation()
        return export
    }
}
