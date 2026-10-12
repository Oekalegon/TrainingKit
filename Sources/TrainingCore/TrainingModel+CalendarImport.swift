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

    /// Adds the planned workouts in `export` as plans, with workouts rebuilt from their template or, failing that, their steps.
    ///
    /// See ``CalendarImportPlanner`` for what is and isn't imported: completed activities become
    /// placeholders (MVP2-107) that HealthKit's own import replaces later, metrics aren't imported,
    /// plans already stored are skipped, and a TRIMP edited outside the app becomes
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
        guard !plan.plans.isEmpty || !plan.activities.isEmpty else { return plan.report }

        // Templates first, then the workouts built from them, then the plans: a failure partway
        // leaves at worst unused library entries, never a workout or plan without what it refers to.
        if !plan.templates.isEmpty, let templateStore = stores.templateStore {
            try await templateStore.upsert(plan.templates)
            templates = try await templateStore.templates()
        }
        if !plan.workouts.isEmpty { try await stores.workoutStore.upsert(plan.workouts) }
        try await stores.planStore.upsert(plan.plans)

        if !plan.activities.isEmpty {
            // Through the import queue, so it can't interleave with a HealthKit import's read and
            // save; and without the anchor, which belongs to HealthKit.
            let result = ImportResult(upserted: plan.activities, deletedSources: [], anchor: nil)
            try await runQueued { try await self.applyImport(result, savingAnchor: false, asOf: today) }
        }

        let dates = (plan.plans.map(\.date) + plan.activities.map(\.start))
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
        let existingActivities = try await stores.activityStore.activityListItems(in: range)
        var existingSources: Set<ActivitySource> = []
        for entry in export.days.flatMap(\.activities) where entry.status != .planned {
            if let uuid = entry.sourceID.flatMap(UUID.init(uuidString:)),
               try await stores.activityStore.activity(source: .healthKit(uuid)) != nil {
                existingSources.insert(.healthKit(uuid))
            }
        }
        let customTemplates = try await stores.templateStore?.templates() ?? []
        return CalendarImportPlanner(estimator: estimator).plan(
            for: export, existingPlans: existingPlans, existingWorkouts: existingWorkouts,
            existingTemplates: BuiltInWorkoutTemplates.all + customTemplates,
            canAddTemplates: stores.templateStore != nil,
            existingActivities: existingActivities, existingSources: existingSources,
            athlete: athlete, today: today
        )
    }
}
