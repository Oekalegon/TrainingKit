import Foundation

/// Importing a ``CalendarExport`` file back into the app (MVP2-103).
extension TrainingModel {
    /// What ``importCalendar(_:asOf:)`` would do with `export`, without changing anything.
    ///
    /// - Parameters:
    ///   - export: The export to import.
    ///   - today: Plans before this day are reported as skipped.
    /// - Returns: The report the import would give.
    /// - Throws: Whatever the stores throw.
    public func calendarImportPreview(_ export: CalendarExport, asOf today: Date = .now) async throws -> CalendarImportReport {
        try await calendarImportPlan(for: export, asOf: today).report
    }

    /// Adds the planned workouts in `export` as plans, with workouts rebuilt from their steps.
    ///
    /// See ``CalendarImportPlanner`` for what is and isn't imported: completed activities and
    /// metrics aren't, plans already stored are skipped, and a TRIMP edited outside the app becomes
    /// the plan's load override. New workouts are saved before the plans that use them, so a
    /// failure partway leaves at worst unused library workouts, never a plan without its workout.
    /// Plans before today are skipped. Afterwards the loaded range is reloaded (the file's days are
    /// loaded only if nothing was loaded yet, since a long file would otherwise load and recompute a
    /// whole season of activities) and plans are reconciled with activities already loaded.
    ///
    /// The plans aren't scheduled in WorkoutKit: that stays with the app's scheduler (MVP2-55).
    ///
    /// - Parameters:
    ///   - export: The export to import.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Returns: What was added, skipped and rejected.
    /// - Throws: Whatever the stores throw.
    @discardableResult
    public func importCalendar(_ export: CalendarExport, asOf today: Date = .now) async throws -> CalendarImportReport {
        let plan = try await calendarImportPlan(for: export, asOf: today)
        guard !plan.plans.isEmpty else { return plan.report }

        if !plan.workouts.isEmpty { try await stores.workoutStore.upsert(plan.workouts) }
        try await stores.planStore.upsert(plan.plans)

        let dates = plan.plans.map(\.date)
        let imported = (dates.min() ?? today)...(dates.max() ?? today)
        try await load(in: loadedRange ?? imported, asOf: today)
        try await reconcilePlans(asOf: today)
        return plan.report
    }

    private func calendarImportPlan(for export: CalendarExport, asOf today: Date) async throws -> CalendarImportPlan {
        let athlete = self.athlete
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        // A day either side, since the file's days are read in the athlete's zone.
        let first = CalendarImportPlanner.date(fromDay: export.firstDay, calendar: calendar) ?? .distantPast
        let last = CalendarImportPlanner.date(fromDay: export.lastDay, calendar: calendar) ?? .distantFuture
        let range = (calendar.date(byAdding: .day, value: -1, to: first) ?? first)...(calendar.date(byAdding: .day, value: 2, to: last) ?? last)
        let existingPlans = try await stores.planStore.plans(in: range)
        let existingWorkouts = try await stores.workoutStore.workouts()
        return CalendarImportPlanner(estimator: estimator).plan(
            for: export, existingPlans: existingPlans, existingWorkouts: existingWorkouts, athlete: athlete, today: today
        )
    }
}
