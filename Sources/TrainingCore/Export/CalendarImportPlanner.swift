import Foundation

/// What importing a ``CalendarExport`` would store (MVP2-103): the new workouts and plans, and the
/// report describing them.
public struct CalendarImportPlan: Sendable, Hashable {
    /// Workouts to add to the library. A workout equal to one already there isn't repeated: the
    /// plans refer to the existing one instead.
    public let workouts: [StructuredWorkout]
    /// Plans to add.
    public let plans: [PlannedActivity]
    /// A summary of the import.
    public let report: CalendarImportReport
}

/// Works out how to import a ``CalendarExport`` without touching any store, so it can be tested on
/// its own and used for a preview.
///
/// Only planned entries are imported. Completed activities are skipped (they come from HealthKit,
/// and the file holds no heart-rate data), and daily metrics are never imported: the model
/// recomputes them. Expected load is kept in one case: a planned entry's TRIMP becomes the plan's
/// load override when it was an override in the file, or when it differs from what the estimator
/// gives for the rebuilt steps, so a load edited outside the app survives. An untouched estimate is
/// left to be recomputed.
///
/// A workout is rebuilt from an entry's `steps`: steps of one `block` form one block, and the
/// block's repetitions are its highest `repetition`. The template link isn't restored, so a
/// workout imported this way can't be re-opened with its template's parameters.
///
/// Entries before today are skipped: such a plan would only show as missed, and the export leaves
/// missed plans out for the same reason.
///
/// A plan counts as a duplicate when the app already has one on the same day for an equal workout
/// (name, sport and blocks). A day can hold the same workout twice: only the occurrences beyond
/// the ones already stored are added.
public struct CalendarImportPlanner: Sendable {
    /// Estimates the load of a rebuilt workout, to tell an edited TRIMP from an untouched estimate.
    public let estimator: PlannedLoadEstimator

    /// Creates a planner.
    ///
    /// - Parameter estimator: Estimates planned load; defaults to the standard one.
    public init(estimator: PlannedLoadEstimator = TRIMPPlanEstimator()) {
        self.estimator = estimator
    }

    /// A TRIMP closer than this to the estimate is treated as the estimate, since exports round.
    static let estimateTolerance = 0.5

    /// Plans the import.
    ///
    /// - Parameters:
    ///   - export: The export to import.
    ///   - existingPlans: Plans already stored for the export's period.
    ///   - existingWorkouts: The workout library.
    ///   - athlete: Supplies the time zone the file's days are read in (the app's own days) and the
    ///     zones the estimator uses.
    ///   - today: Plans on days before this one are skipped.
    /// - Returns: The workouts and plans to add, and the report.
    public func plan(
        for export: CalendarExport,
        existingPlans: [PlannedActivity],
        existingWorkouts: [StructuredWorkout],
        athlete: AthleteProfile,
        today: Date
    ) -> CalendarImportPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let todayStart = calendar.startOfDay(for: today)

        var workoutIDsByKey: [WorkoutKey: UUID] = [:]
        for workout in existingWorkouts {
            workoutIDsByKey[WorkoutKey(workout), default: workout.id] = workout.id
        }
        // How many plans for each (day, workout) are already stored; the file's first occurrences
        // up to that count are duplicates.
        var storedCounts: [PlanKey: Int] = [:]
        for plan in existingPlans {
            storedCounts[PlanKey(day: calendar.startOfDay(for: plan.date), workoutID: plan.workoutID), default: 0] += 1
        }

        var newWorkouts: [StructuredWorkout] = []
        var newPlans: [PlannedActivity] = []
        var rejected: [CalendarImportReport.Rejection] = []
        var duplicates = 0
        var completed = 0
        var past = 0

        for day in export.days {
            for entry in day.activities {
                guard entry.status == .planned else {
                    completed += 1
                    continue
                }
                func reject(_ reason: CalendarImportReport.RejectionReason) {
                    rejected.append(.init(date: day.date, name: entry.name, reason: reason))
                }
                guard let date = Self.date(fromDay: day.date, calendar: calendar) else {
                    reject(.invalidDate)
                    continue
                }
                guard date >= todayStart else {
                    past += 1
                    continue
                }
                guard !entry.steps.isEmpty else {
                    reject(.noSteps)
                    continue
                }
                guard let workout = Self.workout(from: entry) else {
                    reject(.invalidStep)
                    continue
                }

                let key = WorkoutKey(workout)
                let workoutID: UUID
                if let known = workoutIDsByKey[key] {
                    workoutID = known
                } else {
                    workoutID = workout.id
                    workoutIDsByKey[key] = workoutID
                    newWorkouts.append(workout)
                }

                let planKey = PlanKey(day: date, workoutID: workoutID)
                if let stored = storedCounts[planKey], stored > 0 {
                    storedCounts[planKey] = stored - 1
                    duplicates += 1
                    continue
                }
                newPlans.append(PlannedActivity(
                    workoutID: workoutID, date: date, expectedLoadOverride: loadOverride(for: entry, workout: workout, athlete: athlete)
                ))
            }
        }

        return CalendarImportPlan(
            workouts: newWorkouts,
            plans: newPlans,
            report: CalendarImportReport(
                added: newPlans.count, skippedDuplicates: duplicates, skippedPast: past, skippedCompleted: completed,
                rejected: rejected
            )
        )
    }

    private func loadOverride(for entry: CalendarExport.Entry, workout: StructuredWorkout, athlete: AthleteProfile) -> Double? {
        guard let trimp = entry.trimp, trimp.isFinite else { return nil }
        if entry.trimpSource == .override { return trimp }
        let estimated = estimator.estimatedLoad(for: workout, athlete: athlete).value
        return abs(trimp - estimated) > Self.estimateTolerance ? trimp : nil
    }

    private struct WorkoutKey: Hashable {
        let name: String
        let sport: Sport
        let blocks: [WorkoutBlock]

        init(_ workout: StructuredWorkout) {
            (name, sport, blocks) = (workout.name, workout.sport, workout.blocks)
        }
    }

    private struct PlanKey: Hashable {
        let day: Date
        let workoutID: UUID
    }

    static func date(fromDay day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else {
            return nil
        }
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components
        else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Rebuilds a workout from an entry's steps, or `nil` if a step can't be read.
    static func workout(from entry: CalendarExport.Entry) -> StructuredWorkout? {
        var blocks: [WorkoutBlock] = []
        for blockIndex in Set(entry.steps.map(\.block)).sorted() {
            let steps = entry.steps.filter { $0.block == blockIndex }
            let repetitions = steps.map(\.repetition).max() ?? 1
            let firstRepetition = steps.map(\.repetition).min() ?? 1
            var workoutSteps: [WorkoutStep] = []
            for step in steps where step.repetition == firstRepetition {
                guard let converted = workoutStep(from: step) else { return nil }
                workoutSteps.append(converted)
            }
            blocks.append(WorkoutBlock(steps: workoutSteps, repetitions: repetitions))
        }
        return StructuredWorkout(
            name: entry.name ?? entry.template ?? "Imported workout",
            sport: CalendarExportBuilder.sport(identifier: entry.sport),
            blocks: blocks
        )
    }

    private static func workoutStep(from step: CalendarExport.Step) -> WorkoutStep? {
        let kind: StepKind
        switch step.kind {
        case "warmup": kind = .warmup
        case "work": kind = .work
        case "recovery": kind = .recovery
        case "cooldown": kind = .cooldown
        default: return nil
        }
        let goal: StepGoal
        switch step.goal {
        case "time": goal = .time(step.durationSeconds)
        case "distance":
            guard let meters = step.distanceMeters else { return nil }
            goal = .distance(meters)
        case "open": goal = .open
        default: return nil
        }
        return WorkoutStep(kind: kind, goal: goal, target: step.target.flatMap(Self.target))
    }

    private static func target(from target: CalendarExport.Target) -> IntensityTarget? {
        switch target.type {
        case "heartRateZone": return target.zone.map { .heartRateZone($0) }
        case "rpe": return target.rpe.map { .rpe($0) }
        case "heartRateRange":
            guard let low = target.min, let high = target.max else { return nil }
            return .heartRateRange(low, high)
        case "pace", "power":
            guard let low = target.min, let high = target.max, low <= high else { return nil }
            return target.type == "pace" ? .pace(low...high) : .power(low...high)
        default: return nil
        }
    }
}
