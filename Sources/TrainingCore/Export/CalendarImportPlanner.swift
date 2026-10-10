import Foundation

/// What importing a ``CalendarExport`` would store (MVP2-103): the new workouts and plans, and the
/// report describing them.
public struct CalendarImportPlan: Sendable, Hashable {
    /// Templates to add to the library (MVP2-141): those the new plans' workouts were built from,
    /// which the library doesn't already have in an equal form.
    public let templates: [WorkoutTemplate]
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
/// A workout is rebuilt from the template its entry names (MVP2-141) when the library has it or the
/// file defines it: instantiated with the entry's parameter values, so it can be re-opened with its
/// template's parameters. A template in the file is added to the library, unless the library holds
/// an equal one (same sport, parameters and blocks; the name may differ), which the workouts are
/// linked to instead. One whose id is already taken by a different definition is added as a copy
/// with a new id, so neither is altered. Only templates used by a plan that is added are added.
///
/// An entry with no usable template (a file written before templates were exported, a template the
/// library lacks and the file doesn't define, or a definition that can't be read) is rebuilt from its
/// `steps` instead: steps of one `block` form one block, and the block's repetitions are its highest
/// `repetition`. Such a workout has no template link.
///
/// Entries before today are skipped: such a plan would only show as missed, and the export leaves
/// missed plans out for the same reason.
///
/// A plan counts as a duplicate when the app already has one on the same day for an equal workout
/// (name, sport and blocks, whatever template it was built from). A day can hold the same workout
/// twice: only the occurrences beyond the ones already stored are added.
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
    ///   - existingTemplates: The templates the library offers, built-in and custom, archived ones
    ///     included.
    ///   - canAddTemplates: Whether templates can be stored. Without a template store, a template
    ///     the library lacks isn't added, and its workouts are rebuilt from their steps.
    ///   - athlete: Supplies the time zone the file's days are read in (the app's own days) and the
    ///     zones the estimator uses.
    ///   - today: Plans on days before this one are skipped.
    /// - Returns: The workouts and plans to add, and the report.
    public func plan(
        for export: CalendarExport,
        existingPlans: [PlannedActivity],
        existingWorkouts: [StructuredWorkout],
        existingTemplates: [WorkoutTemplate] = [],
        canAddTemplates: Bool = true,
        athlete: AthleteProfile,
        today: Date
    ) -> CalendarImportPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let todayStart = calendar.startOfDay(for: today)

        // Every workout the library has or this import adds, by what it is, so an entry can reuse one.
        var workoutsByKey: [WorkoutKey: [StructuredWorkout]] = [:]
        for workout in existingWorkouts {
            workoutsByKey[WorkoutKey(workout), default: []].append(workout)
        }
        // How many plans for each (day, workout) are already stored; the file's first occurrences
        // up to that count are duplicates.
        let existingByID = Dictionary(existingWorkouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var storedCounts: [PlanKey: Int] = [:]
        for plan in existingPlans {
            guard let workout = existingByID[plan.workoutID] else { continue }
            storedCounts[PlanKey(day: calendar.startOfDay(for: plan.date), key: WorkoutKey(workout)), default: 0] += 1
        }

        var templates = TemplateResolver(
            fileTemplates: export.templates, library: existingTemplates, canAdd: canAddTemplates
        )
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
                let fromTemplate = templates.workout(for: entry)
                guard fromTemplate != nil || !entry.steps.isEmpty else {
                    reject(.noSteps)
                    continue
                }
                guard let workout = fromTemplate?.workout ?? Self.workout(from: entry) else {
                    reject(.invalidStep)
                    continue
                }

                let key = WorkoutKey(workout)
                let planKey = PlanKey(day: date, key: key)
                if let stored = storedCounts[planKey], stored > 0 {
                    storedCounts[planKey] = stored - 1
                    duplicates += 1
                    continue
                }

                // Reuse an equal workout, but never one built from another template (or other values)
                // when this one has a template link to keep; a workout with no link takes any.
                let candidates = workoutsByKey[key] ?? []
                let existing = candidates.first {
                    workout.templateID == nil
                        || ($0.templateID == workout.templateID && $0.parameterValues == workout.parameterValues)
                }
                let workoutID: UUID
                if let existing {
                    workoutID = existing.id
                } else {
                    workoutID = workout.id
                    workoutsByKey[key, default: []].append(workout)
                    newWorkouts.append(workout)
                }
                if let fromTemplate { templates.commit(fromTemplate.templateFileID) }
                newPlans.append(PlannedActivity(
                    workoutID: workoutID, date: date, expectedLoadOverride: loadOverride(for: entry, workout: workout, athlete: athlete)
                ))
            }
        }

        return CalendarImportPlan(
            templates: templates.added,
            workouts: newWorkouts,
            plans: newPlans,
            report: CalendarImportReport(
                added: newPlans.count, skippedDuplicates: duplicates, skippedPast: past, skippedCompleted: completed,
                rejected: rejected,
                templatesAdded: templates.addedCount, templatesLinked: templates.linkedCount,
                templatesCopied: templates.copiedCount, templatesRejected: templates.rejectedCount
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
        let key: WorkoutKey
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

    /// The step kind a file's identifier names, or `nil` for one this version doesn't know.
    static func stepKind(identifier: String) -> StepKind? {
        switch identifier {
        case "warmup": .warmup
        case "work": .work
        case "recovery": .recovery
        case "cooldown": .cooldown
        default: nil
        }
    }

    private static func workoutStep(from step: CalendarExport.Step) -> WorkoutStep? {
        guard let kind = stepKind(identifier: step.kind) else { return nil }
        let goal: StepGoal
        switch step.goal {
        case "time": goal = .time(step.durationSeconds)
        case "distance":
            guard let meters = step.distanceMeters else { return nil }
            goal = .distance(meters)
        case "open": goal = .open
        default: return nil
        }
        return WorkoutStep(kind: kind, goal: goal, target: step.target.flatMap(Self.target(from:)))
    }

    static func target(from target: CalendarExport.Target) -> IntensityTarget? {
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

/// Decides which library template each file template is, as the planner reads the file (MVP2-141).
private struct TemplateResolver {
    /// A file template's fate: an equal or same-id template the library has, or one to add.
    private enum Resolution {
        case existing(WorkoutTemplate)
        case new(WorkoutTemplate, isCopy: Bool)
    }

    /// A workout built from a template, and the file id of the template to commit once the workout's
    /// plan is added.
    struct Built {
        let workout: StructuredWorkout
        let templateFileID: UUID
    }

    private var library: [WorkoutTemplate]
    private var libraryByID: [UUID: WorkoutTemplate]
    private var resolutions: [UUID: Resolution] = [:]
    private var committed: Set<UUID> = []
    /// Templates to add, in the order they were first used.
    private(set) var added: [WorkoutTemplate] = []
    private(set) var addedCount = 0
    private(set) var linkedCount = 0
    private(set) var copiedCount = 0
    private(set) var rejectedCount = 0

    init(fileTemplates: [CalendarExport.Template], library: [WorkoutTemplate], canAdd: Bool) {
        self.library = library
        libraryByID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for fileTemplate in fileTemplates {
            guard let fileID = UUID(uuidString: fileTemplate.id), var template = fileTemplate.workoutTemplate() else {
                rejectedCount += 1
                continue
            }
            // Equal in what it does, whatever it's called; a live one in preference to an archived one.
            let equal = self.library.first { !$0.isArchived && Self.isEqual($0, template) }
                ?? self.library.first { Self.isEqual($0, template) }
            if let equal {
                resolutions[fileID] = .existing(equal)
                continue
            }
            guard canAdd else {
                rejectedCount += 1
                continue
            }
            let isCopy = libraryByID[template.id] != nil
            if isCopy {
                template = WorkoutTemplate(
                    name: template.name, titleName: template.titleName, sport: template.sport,
                    parameters: template.parameters, blocks: template.blocks
                )
            }
            resolutions[fileID] = .new(template, isCopy: isCopy)
            // Later file templates may equal this one.
            self.library.append(template)
        }
    }

    /// The workout `entry` describes, built from its template, or `nil` when it has none the library
    /// or the file provides.
    mutating func workout(for entry: CalendarExport.Entry) -> Built? {
        guard let fileID = entry.templateID.flatMap(UUID.init(uuidString:)) else { return nil }
        let template: WorkoutTemplate
        switch resolutions[fileID] {
        case .existing(let existing): template = existing
        case .new(let new, _): template = new
        case nil:
            // Not defined in the file: a built-in template, or one the library already has by id.
            guard let known = libraryByID[fileID] else { return nil }
            template = known
        }
        guard let workout = try? template.instantiate(
            name: entry.name, values: entry.parameterValues ?? [:]
        ) else { return nil }
        return Built(workout: workout, templateFileID: fileID)
    }

    /// Counts the template as used by an added plan, and queues it for adding if it is new.
    mutating func commit(_ fileID: UUID) {
        guard committed.insert(fileID).inserted, let resolution = resolutions[fileID] else { return }
        switch resolution {
        case .existing:
            linkedCount += 1
        case .new(let template, let isCopy):
            added.append(template)
            if isCopy { copiedCount += 1 } else { addedCount += 1 }
        }
    }

    /// Whether two templates do the same thing: the id, name and archived state don't count.
    private static func isEqual(_ lhs: WorkoutTemplate, _ rhs: WorkoutTemplate) -> Bool {
        lhs.sport == rhs.sport && lhs.parameters == rhs.parameters && lhs.blocks == rhs.blocks
    }
}
