import Foundation

/// The plan generator (MVP5-145): composes the finished pieces of the MVP5 plan generator into a
/// ``PlanProposal`` for a ``PlanRequest``.
///
/// `PlanGenerator` is the ``PlanCandidateProvider`` ``PlanAdjuster`` has been waiting for.
/// ``generate()`` hands itself to the adjust loop, which asks ``candidate(levers:today:)`` for the
/// first plan (``PlanLevers/none``) and for each adjusted one. Each candidate is built from scratch,
/// as a pure function of the request and the levers:
///
/// 1. ``LeadTimeCompromiser`` fits the request's macro into the days from `start` to race day
///    (counted inclusively, so 16 weeks of 7 days is 16 micros) and reports what it dropped or
///    shortened. A conditioning phase it drops against the athlete's wish also gives
///    ``PlanCompromise/overriddenPreference(_:)``.
/// 2. ``KeyRaceLayout`` lays out the micros back from the target race and gives each secondary race
///    its taper and recovery micros. Micros in ``PlanLevers/downWeeks`` become `.recovery`.
/// 3. ``CycleLayoutBuilder`` turns the micros into the macro, meso and micro ``TrainingCycle``s.
/// 4. ``VolumeCurveBuilder`` gives each micro a volume, from the request's starting and peak volume
///    (the peak lowered to ``PlanPreferences/maxWeeklyVolume`` for running) times the lever for the micro.
///    A distance becomes a duration at the easy pace (zone 2) of the athlete's pace model. The curve is a
///    ceiling: each micro is sized, by bisection, to the largest volume under its ceiling (the build
///    volume of its place in the ramp, with no recovery or taper fraction) that ends in the middle of
///    its TSB zone (``TSBZone/midpoint(guardrails:)``): training for a build micro, recovery for a
///    recovery micro, race on race day for a taper micro. A micro already fresher than its aim at the
///    ceiling stays at the ceiling, a micro that no volume brings to its aim gets the lightest one tried,
///    and while the aimed day is still warming up (no history) the curve's own volume, with its
///    recovery and taper fractions, is used. The aim uses the paradigm's guardrail overrides, like the
///    evaluator. With volumes close to the athlete's history the ceiling is often not enough to reach
///    -20, and the micros then end fresher than that. A micro that ends in another TSB zone than its
///    role aims at is ``PlanCompromise/sizingMissedZone(microStart:aimed:reached:)``, unless the adjust loop
///    lowered it on purpose.
/// 5. ``DayAssigner`` places the micro's hard sessions, long runs and easy runs on the athlete's days
///    and day parts, with the spacing of earlier micros passed as `preceding` and the days the demanding
///    workouts of earlier micros want free after them (``RecoveryDays/after``) as `recoveryAfter`, a
///    minimum it aims for. Nothing is placed on the day of a race. A session it cannot place is
///    ``PlanCompromise/unplacedSession(microStart:_:)``.
/// 6. Each run gets a ``SessionProfile`` (the paradigm's profile for the micro's phase and the run's
///    session type, else one with the session type only; a micro's hard runs take the phase's hard
///    profiles in turn, so a structural micro with two gets a fast and an endurance quality session). ``SessionProfile/progressedWorkLength(microIndex:of:)``
///    steps the work length across the phase, and ``TemplateFitter`` picks and sizes a template for an
///    equal share of the micro's duration, with the previous micro's templates (only that one) for rotation. No
///    template is ``PlanCompromise/missingTemplate(microStart:_:)`` and the run is left out. A run whose
///    template wants more days free of demanding workouts around it than its neighbours leave
///    (``RecoveryDays``) is fitted again without that template; when no other template fits it keeps the
///    day and the shortfall is a ``PlanCompromise/recoveryDaysShort(day:template:neededDays:availableDays:)``.
///    A profile with a race-target fraction on a pace target only takes templates whose hard work zone holds
///    the phase pace; when none does, a hard step that could not be given its target is
///    ``PlanCompromise/unresolvedStep(microStart:template:reason:)``, once per template and reason in a micro.
/// 7. ``StepTargetResolver`` writes the athlete's zones and the profile's race-target fraction into the
///    steps, and the run becomes a ``PlannedActivity`` in the micro's cycle.
/// 8. ``PlannedIntensityClassifier`` makes the ``PlanSession``s, and ``DailyLoadSeries`` with
///    ``FitnessMetricsCalculator`` project the series, from the request's history, through race day.
///    The target race and the other races add their load on their day (``Race/expectedLoadOverride``
///    or an estimate), whatever their priority.
///
/// Levers act in steps 2, 4 and 6: ``PlanLevers/volumeScales`` multiply the micro's sized volume (so the adjust loop can lower a micro below its TSB aim),
/// ``PlanLevers/easedDays`` turn a hard or long run into an easy one, ``PlanLevers/droppedDays``
/// leave the day's runs out.
///
/// The generator is deterministic and reads no clock: the same request gives the same dates,
/// templates, values and series. The ids of cycles, workouts and planned workouts are fresh random
/// `UUID`s on every build. It checks for cancellation before each candidate and each micro and then
/// throws `CancellationError`.
///
/// Not done: steps the resolver could not resolve, secondary races the layout skipped, a plan that
/// starts after `start` because the macro is shorter than the lead time, and a long run over
/// ``PlanPreferences/maxLongRun(for:targetRace:)`` are not reported as compromises; the request's
/// volume must not be in TRIMP; the two or more runs of one day all carry the start of that day.
public struct PlanGenerator: PlanCandidateProvider {
    /// The request every candidate is built from.
    public let request: PlanRequest
    /// The request's templates by id, for the recovery days of a fitted run.
    private let templatesByID: [UUID: WorkoutTemplate]

    /// The request's paradigm with the spacing the plan's preferences ask for
    /// (``PlanPreferences/minDaysBetweenHardSessions``), which the day assignment and the evaluation share.
    /// A paradigm without a spacing rule gets one from the preference.
    private var paradigm: TrainingParadigm {
        var paradigm = request.paradigm
        if let spacing = request.preferences.minDaysBetweenHardSessions { paradigm.minDaysBetweenHardSessions = spacing }
        return paradigm
    }

    /// Creates a generator.
    ///
    /// - Parameter request: What to build.
    public init(request: PlanRequest) {
        self.request = request
        templatesByID = Dictionary(request.templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Builds the proposal for `request` with a new generator.
    ///
    /// - Parameter request: What to build.
    /// - Returns: See ``generate()``.
    /// - Throws: See ``generate()``.
    public static func generate(_ request: PlanRequest) async throws -> PlanProposal {
        try await PlanGenerator(request: request).generate()
    }

    /// Builds the first plan and lets ``PlanAdjuster`` adjust it until it has no risk or its bound is hit.
    ///
    /// The races are checked for race-day TSB at the start of their day in the athlete's time zone.
    ///
    /// - Returns: The proposal: acceptable, or the plan as it stands with its risks. Its compromises
    ///   are those of the candidate and the adjustments the loop kept; its
    ///   ``PlanProposal/calibrationWarning`` is set when the paradigm is not calibrated for the race.
    /// - Throws: ``PlanGeneratorError`` when no plan can be built, or `CancellationError`.
    public func generate() async throws -> PlanProposal {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = request.athlete.timeZone
        // The series is keyed on starts of day, and the race-day TSB rule looks the race up by its date.
        let races = ([request.targetRace] + request.otherRaces).map { race -> Race in
            var race = race
            race.date = calendar.startOfDay(for: race.date)
            return race
        }
        let adjuster = PlanAdjuster(
            races: races,
            paradigm: paradigm,
            targetRace: request.targetRace,
            guardrails: request.guardrails
        )
        return try await adjuster.propose(using: self, today: request.today)
    }

    /// Builds the plan with `levers` applied.
    ///
    /// - Parameters:
    ///   - levers: The changes to apply; ``PlanLevers/none`` for the first plan.
    ///   - today: The current day, used for the projected series.
    /// - Returns: The plan with its sessions, projected metrics and compromises.
    /// - Throws: ``PlanGeneratorError``, or `CancellationError`.
    public func candidate(levers: PlanLevers, today: Date) async throws -> PlanCandidate {
        try Task.checkCancellation()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = request.athlete.timeZone
        var compromises: [PlanCompromise] = []

        let (micros, macro) = try layout(levers: levers, calendar: calendar, compromises: &compromises)
        let cycles = CycleLayoutBuilder().cycles(from: micros, macro: macro, race: request.targetRace)
        let microCycles = cycles.filter { $0.level == .micro }
        let volumes = try volumeTargets(for: micros, curve: request.volumeCurve)
        let ceilings = try volumeTargets(for: micros, curve: ceilingCurve)
        // Analysing the templates does not depend on the micro, the volume or the levers: once per candidate.
        let prepared = TemplateFitter.prepare(request.templates, athlete: request.athlete)

        var planned: [PlannedActivity] = []
        var workouts: [StructuredWorkout] = []
        var planSessions: [PlanSession] = []
        var overWeeklyLimit = false
        var hardDates: [Date] = []
        var longDates: [Date] = []
        var previousTemplates: [UUID] = []
        var demands: [Demand] = []
        var reportedPlanProblems: Set<UnresolvedReason> = []
        let spacesLong = paradigm.resolved(for: request.targetRace).spacesLongRunsAsHard
        let assigner = DayAssigner(paradigm: paradigm)
        let weeklyLimitSeconds = try request.preferences.maxWeeklyVolume[.running].map(durationSeconds(of:))
        let races = [request.targetRace] + request.otherRaces
        let raceDays = races.map { calendar.startOfDay(for: $0.date) }

        for (index, micro) in micros.enumerated() {
            try Task.checkCancellation()
            let microStart = micro.dateRange.lowerBound
            let volume = volumes[index]
            let leverScale = levers.volumeScale(forMicro: microStart)
            let assignment = assigner.assign(
                micro: micro.dateRange,
                availability: request.preferences.runAvailability,
                hardCount: request.hardSessionsPerMicro,
                longCount: request.longRunsPerMicro,
                preceding: hardDates + (spacesLong ? longDates : []),
                precedingLongRuns: longDates,
                recoveryAfter: Dictionary(demands.map { ($0.date, $0.recovery.after) }, uniquingKeysWith: max),
                raceDays: raceDays,
                targetRace: request.targetRace,
                calendar: calendar
            )
            let phaseMicros = micros.indices.filter { micros[$0].phase == micro.phase }
            let position = phaseMicros.firstIndex(of: index) ?? 0

            func build(_ seconds: TimeInterval) throws -> MicroBuild {
                try buildMicro(
                    assignment, micro: micro, cycleID: microCycles[index].id, seconds: seconds, position: position,
                    phaseCount: phaseMicros.count, previous: previousTemplates, levers: levers, carried: demands, prepared: prepared, calendar: calendar
                )
            }
            func endTSB(of built: MicroBuild, on day: Date) -> FitnessMetrics? {
                projectedMetrics(
                    plans: planned + built.planned, workouts: workouts + built.workouts, races: races,
                    through: day, calendar: calendar, today: today
                ).first { $0.day == day }
            }

            // The lever lowers the sized volume (it is the adjust loop's own step), it is not another ceiling.
            let curveSeconds = try durationSeconds(of: volume.target) * leverScale
            let ceilingSeconds = try durationSeconds(of: ceilings[index].target)
            var built: MicroBuild
            var missedZone: PlanCompromise?
            if let aim = sizingAim(for: micro, raceDays: raceDays, calendar: calendar) {
                let top = try build(ceilingSeconds)
                if let topMetric = endTSB(of: top, on: aim.day), !topMetric.isWarmingUp {
                    var chosen = (scale: 1.0, build: top, tsb: topMetric.tsb)
                    if topMetric.tsb < aim.tsb {
                        // Too tired at the ceiling: the largest volume that still ends at the aim, found by
                        // bisection; when no volume reaches it, the lightest one tried.
                        var (low, high) = (0.0, 1.0)
                        var reached: (scale: Double, build: MicroBuild, tsb: Double)?
                        var lightest = chosen
                        for _ in 0..<Self.sizingSteps {
                            let scale = (low + high) / 2
                            let probe = try build(ceilingSeconds * scale)
                            guard let metric = endTSB(of: probe, on: aim.day) else { break }
                            if scale < lightest.scale { lightest = (scale, probe, metric.tsb) }
                            if metric.tsb < aim.tsb { high = scale } else { low = scale; reached = (scale, probe, metric.tsb) }
                            if abs(metric.tsb - aim.tsb) < Self.sizingTolerance { reached = (scale, probe, metric.tsb); break }
                        }
                        chosen = reached ?? lightest
                    }
                    built = leverScale == 1 ? chosen.build : try build(ceilingSeconds * chosen.scale * leverScale)
                    // A micro the adjust loop lowered ends fresher than its aim on purpose, and that adjustment is reported.
                    let reachedZone = TSBZone(tsb: chosen.tsb, guardrails: aim.guardrails)
                    if leverScale == 1, reachedZone != aim.zone {
                        missedZone = .sizingMissedZone(microStart: microStart, aimed: aim.zone, reached: reachedZone)
                    }
                } else {
                    // Still warming up (no history to aim from): the curve's own volume.
                    built = try build(curveSeconds)
                }
            } else {
                built = try build(curveSeconds)
            }

            compromises += assignment.dropped.map { .unplacedSession(microStart: microStart, $0) }
            compromises += built.compromises
            for reason in built.planProblems where reportedPlanProblems.insert(reason).inserted {
                compromises.append(.unresolvedPlanTarget(reason: reason))
            }
            compromises += missedZone.map { [$0] } ?? []
            workouts += built.workouts
            planned += built.planned
            planSessions += built.sessions
            hardDates += built.hardDays
            longDates += built.longDays
            previousTemplates = built.templates
            demands += built.demands
            if let weeklyLimitSeconds, built.fittedSeconds * 7 / Double(volume.lengthDays) > weeklyLimitSeconds * (1 + 1e-9) {
                overWeeklyLimit = true
            }
        }
        if overWeeklyLimit { compromises.append(.overriddenPreference(.maxWeeklyVolume)) }

        let metrics = projectedMetrics(
            plans: planned, workouts: workouts, races: races, through: calendar.startOfDay(for: request.targetRace.date),
            calendar: calendar, today: today
        )
        let sessions = (request.recentSessions + planSessions).enumerated()
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map(\.element)
        return PlanCandidate(
            cycles: cycles, plannedActivities: planned.sorted { $0.date < $1.date }, workouts: workouts,
            sessions: sessions, metrics: metrics, compromises: compromises
        )
    }

    /// The volume curve with every fraction at 1: each micro's ceiling is the build volume of its place
    /// in the ramp (the last build micro's for a recovery, the peak for a taper), because the sizing
    /// below, not a fixed fraction, decides how much lighter it is.
    private var ceilingCurve: VolumeCurveBuilder {
        var curve = request.volumeCurve
        curve.recoveryLoadFraction = 1
        curve.taperStartFraction = 1
        curve.taperEndFraction = 1
        curve.raceFraction = 1
        return curve
    }

    /// Bisection steps and the TSB distance (in points) at which the sizing of a micro stops.
    private static let sizingSteps = 12
    private static let sizingTolerance = 0.5

    /// Where a micro should end: the middle of the TSB zone of its role (training for a build micro,
    /// recovery for a recovery micro) on its last day, and the middle of the race zone on race day for
    /// a taper micro (the race inside it, else its last day). `nil` for a micro with no zone.
    private func sizingAim(
        for micro: Microcycle, raceDays: [Date], calendar: Calendar
    ) -> (day: Date, tsb: Double, zone: TSBZone, guardrails: PlanGuardrails)? {
        // The evaluator's guardrails: the paradigm's overrides applied, as `PlanEvaluator` does.
        let guardrails = paradigm.resolved(for: request.targetRace).guardrailOverrides.applied(to: request.guardrails)
        let zone: TSBZone
        var day = calendar.startOfDay(for: micro.dateRange.upperBound)
        switch micro.loadRole {
        case .build: zone = .training
        case .recovery: zone = .recovery
        case .taper, .race:
            zone = .race
            if let raceDay = raceDays.filter({ micro.dateRange.contains($0) }).min() { day = raceDay }
        }
        return zone.midpoint(guardrails: guardrails).map { (day, $0, zone, guardrails) }
    }

    /// One micro's runs, fitted for `seconds`, before they are added to the plan.
    private struct MicroBuild {
        var planned: [PlannedActivity] = []
        var workouts: [StructuredWorkout] = []
        var sessions: [PlanSession] = []
        var templates: [UUID] = []
        var fittedSeconds: TimeInterval = 0
        var hardDays: [Date] = []
        var longDays: [Date] = []
        var demands: [Demand] = []
        var compromises: [PlanCompromise] = []
        /// Reasons a hard step could not be given its target that do not depend on the template, for the plan to report once.
        var planProblems: [UnresolvedReason] = []
    }

    /// A demanding workout of the plan: its day and the days it wants free around it.
    private struct Demand {
        let date: Date
        let recovery: RecoveryDays
    }

    /// Steps 5 and 6 for one micro: the runs of `assignment` fitted to an equal share of `seconds`.
    ///
    /// A run whose template wants more days around it than its neighbours leave (``RecoveryDays``:
    /// the demanding workouts `carried` in from earlier micros, the ones already fitted in this micro
    /// and the ones still to come, which count with their default) is fitted again without that
    /// template, until one fits or none is left. When none is left the best fit keeps the day and the
    /// shortfall is a ``PlanCompromise/recoveryDaysShort(day:template:neededDays:availableDays:)``.
    private func buildMicro(
        _ assignment: DayAssignmentResult, micro: Microcycle, cycleID: UUID, seconds: TimeInterval, position: Int,
        phaseCount: Int, previous: [UUID], levers: PlanLevers, carried: [Demand], prepared: [TemplateFitter.Prepared], calendar: Calendar
    ) throws -> MicroBuild {
        var built = MicroBuild()
        let fits = TemplateFits(prepared: prepared)
        var reportedProblems: Set<ProblemKey> = []
        let share = seconds / Double(max(assignment.assignments.count, 1))
        var hardIndex = 0
        let runs = assignment.assignments.filter { !levers.droppedDays.contains($0.day) }
        let defaultAfter = paradigm.minDaysBetweenHardSessions.flatMap { $0 > 0 ? $0 : nil }
        let longNeedsRecovery = paradigm.resolved(for: request.targetRace).spacesLongRunsAsHard
        func isEased(_ run: DayAssignment) -> Bool {
            levers.easedDays.contains(run.day) && Self.easedTypes.contains(run.runType)
        }
        /// What a run still to be fitted wants: the default of its run type.
        func defaultDemand(of run: DayAssignment) -> Demand? {
            guard !isEased(run), let defaultAfter else { return nil }
            let demanding = Self.hardTypes.contains(run.runType) || (run.runType == .long && longNeedsRecovery)
            return demanding ? Demand(date: run.day, recovery: RecoveryDays(before: 0, after: defaultAfter)) : nil
        }

        for (index, run) in runs.enumerated() {
            let eased = isEased(run)
            let later = runs[(index + 1)...].compactMap(defaultDemand(of:))
            let thisHardIndex = hardIndex
            if Self.hardTypes.contains(run.runType) && !eased { hardIndex += 1 }
            let (fitted, shortfall) = try fitHonouringRecoveryDays(
                run, on: run.day, neighbours: Neighbours(carried: carried, inMicro: built.demands, later: later), calendar: calendar
            ) { excluded in
                try fitRun(
                    run, eased: eased, hardIndex: thisHardIndex, micro: micro, position: position, phaseCount: phaseCount,
                    share: share, previous: previous, cycleID: cycleID, excluded: excluded, fits: fits
                )
            }
            if let shortfall {
                built.compromises.append(.recoveryDaysShort(
                    day: run.day, template: shortfall.template, neededDays: shortfall.needed, availableDays: shortfall.available
                ))
            }
            guard case .run(let result) = fitted else {
                if case .missing(let profile) = fitted { built.compromises.append(.missingTemplate(microStart: micro.dateRange.lowerBound, profile)) }
                continue
            }
            built.workouts.append(result.workout)
            built.planned.append(result.planned)
            built.sessions.append(result.session)
            built.templates.append(result.templateID)
            if let reason = result.unresolvedReason {
                if reason.dependsOnTemplate {
                    if reportedProblems.insert(ProblemKey(template: result.templateName, reason: reason)).inserted {
                        built.compromises.append(.unresolvedStep(microStart: micro.dateRange.lowerBound, template: result.templateName, reason: reason))
                    }
                } else if !built.planProblems.contains(reason) {
                    built.planProblems.append(reason)
                }
            }
            built.fittedSeconds += result.seconds
            if let recovery = recoveryDays(of: result.templateID, defaultAfter: defaultAfter, longNeedsRecovery: longNeedsRecovery) {
                built.demands.append(Demand(date: run.day, recovery: recovery))
            }
            if Self.hardTypes.contains(run.runType) && !eased { built.hardDays.append(run.day) }
            if run.runType == .long && !eased { built.longDays.append(run.day) }
        }
        return built
    }

    /// The demanding workouts around one run: those carried in from earlier micros, those already fitted
    /// in this micro and those still to come (with their default days).
    private struct Neighbours {
        let carried: [Demand]
        let inMicro: [Demand]
        let later: [Demand]
    }

    /// How far a template is from the days it wants free, against the neighbour that falls shortest.
    private struct RecoveryShortfall {
        let template: String
        let needed: Int
        let available: Int
    }

    /// Fits a run with `fit`, and again without each template that wants more days around it than its
    /// `neighbours` leave, until one fits or none is left.
    ///
    /// - Parameters:
    ///   - run: The run to fit.
    ///   - day: The run's day.
    ///   - neighbours: The demanding workouts around the run.
    ///   - calendar: The athlete's calendar.
    ///   - fit: Fits the run without the given templates.
    /// - Returns: The fit to keep and, when the best fit is short of the days it wants and nothing else
    ///   fits, the shortfall of that best fit: the run keeps its day and the caller reports it.
    private func fitHonouringRecoveryDays(
        _ run: DayAssignment, on day: Date, neighbours: Neighbours, calendar: Calendar,
        fit: (Set<UUID>) throws -> RunFit
    ) throws -> (RunFit, RecoveryShortfall?) {
        let best = try fit([])
        guard case .run(var attempt) = best,
              let shortfall = recoveryShortfall(of: attempt, on: day, neighbours: neighbours, calendar: calendar) else { return (best, nil) }
        var excluded: Set<UUID> = []
        while true {
            excluded.insert(attempt.templateID)
            guard case .run(let next) = try fit(excluded) else { return (best, shortfall) }
            guard recoveryShortfall(of: next, on: day, neighbours: neighbours, calendar: calendar) != nil else { return (.run(next), nil) }
            attempt = next
        }
    }

    /// The days the template `id` wants free around its workouts in this plan, or `nil` for none.
    private func recoveryDays(of id: UUID, defaultAfter: Int?, longNeedsRecovery: Bool) -> RecoveryDays? {
        templatesByID[id]?
            .effectiveRecoveryDays(defaultAfter: defaultAfter, longRunsNeedRecovery: longNeedsRecovery)
    }

    /// How far a fitted run is from the days its template wants free, against the demanding workouts
    /// around `day`: the template's name, the days needed and the days available to the neighbour that
    /// falls shortest. `nil` when the template wants nothing or gets enough.
    ///
    /// A workout `carried` in from an earlier micro is compared in full, as it was fitted without
    /// knowing this day. One already fitted `inMicro` was fitted knowing this day by its default, so
    /// only what this template adds (its days before) can be short here; the rest is that workout's own
    /// report. `later` workouts are not fitted yet and count with their default.
    private func recoveryShortfall(
        of run: FittedRun, on day: Date, neighbours: Neighbours, calendar: Calendar
    ) -> RecoveryShortfall? {
        let defaultAfter = paradigm.minDaysBetweenHardSessions.flatMap { $0 > 0 ? $0 : nil }
        let longNeedsRecovery = paradigm.resolved(for: request.targetRace).spacesLongRunsAsHard
        guard let own = recoveryDays(of: run.templateID, defaultAfter: defaultAfter, longNeedsRecovery: longNeedsRecovery),
              let name = templatesByID[run.templateID]?.name else { return nil }
        func days(from start: Date, to end: Date) -> Int { calendar.dateComponents([.day], from: start, to: end).day ?? Int.max }
        var worst: (needed: Int, available: Int)?
        func note(needed: Int, available: Int) {
            guard available < needed else { return }
            if let current = worst, needed - available <= current.needed - current.available { return }
            worst = (needed, available)
        }
        for neighbour in neighbours.carried {
            note(needed: neighbour.recovery.after + own.before, available: days(from: neighbour.date, to: day))
        }
        for neighbour in neighbours.inMicro {
            let available = days(from: neighbour.date, to: day)
            // Its own days after are its report; only the days this template wants before it are added here.
            if available >= neighbour.recovery.after { note(needed: neighbour.recovery.after + own.before, available: available) }
        }
        for neighbour in neighbours.later {
            note(needed: own.after + neighbour.recovery.before, available: days(from: day, to: neighbour.date))
        }
        return worst.map { RecoveryShortfall(template: name, needed: $0.needed, available: $0.available) }
    }

    /// A template and why one of its hard steps could not be resolved: reported once per micro.
    private struct ProblemKey: Hashable {
        let template: String
        let reason: UnresolvedReason
    }

    /// What a fit depends on: runs of one micro with the same profile, work length and rotation memory
    /// get the same ``TemplateFit`` for the same share of the volume.
    private struct FitKey: Hashable {
        let profile: SessionProfile
        let targetSeconds: TimeInterval
        let workLength: TimeInterval?
        let previous: [UUID]
        let excluded: Set<UUID>
        /// The pace the phase asks for, which decides which templates take part.
        let phase: TemplateFitter.PhasePace?
    }

    /// The ``TemplateFit``s made while building one micro, so equal runs (the easy runs of a micro, say)
    /// are fitted once (MVP5-151). A fit is a pure function of its key, so nothing changes but the time.
    private final class TemplateFits {
        /// The request's templates the fitter can use, prepared once per candidate.
        let prepared: [TemplateFitter.Prepared]
        private var fits: [FitKey: TemplateFit] = [:]

        init(prepared: [TemplateFitter.Prepared]) {
            self.prepared = prepared
        }

        func fit(for key: FitKey, make: () -> TemplateFit) -> TemplateFit {
            if let known = fits[key] { return known }
            let made = make()
            fits[key] = made
            return made
        }
    }

    private enum RunFit {
        case run(FittedRun)
        case missing(SessionProfile)
    }

    private struct FittedRun {
        let workout: StructuredWorkout
        let planned: PlannedActivity
        let session: PlanSession
        let templateID: UUID
        let templateName: String
        let seconds: TimeInterval
        /// Why a hard work step could not be given the target it was asked for, if one could not.
        let unresolvedReason: UnresolvedReason?
    }

    /// Steps 6 and 7 for one run: profile, template fit, instantiation, step targets, and the
    /// planned workout and session that come of it.
    private func fitRun(
        _ run: DayAssignment, eased: Bool, hardIndex: Int, micro: Microcycle, position: Int, phaseCount: Int,
        share: TimeInterval, previous: [UUID], cycleID: UUID, excluded: Set<UUID> = [], fits: TemplateFits
    ) throws -> RunFit {
        let profile = profile(for: run, eased: eased, hardIndex: hardIndex, position: position, phase: micro.phase)
        let workLength = profile.progressedWorkLength(microIndex: position, of: phaseCount)
        let raceTargetFraction = profile.progressedRaceTargetFraction(microIndex: position, of: phaseCount)
        // The pace the resolver puts on the work steps, as it works it out: a pace target divided by the fraction.
        var phase: TemplateFitter.PhasePace?
        if let fraction = raceTargetFraction, fraction.isFinite, fraction > 0,
           case .pace(let seconds)? = request.targetRace.specificPhaseTarget, seconds.isFinite, seconds > 0 {
            phase = TemplateFitter.PhasePace(secondsPerKilometer: seconds / fraction, paceModel: request.athlete.paceModel(asOf: run.day))
        }
        let key = FitKey(profile: profile, targetSeconds: share, workLength: workLength, previous: previous, excluded: excluded, phase: phase)
        let fit = fits.fit(for: key) {
            TemplateFitter.fit(
                profile: profile,
                targetSeconds: share,
                prepared: excluded.isEmpty ? fits.prepared : fits.prepared.filter { !excluded.contains($0.template.id) },
                phase: phase,
                previous: previous,
                workLength: workLength,
                athlete: request.athlete
            )
        }
        guard case .fit(let choice) = fit else { return .missing(profile) }
        let workout: StructuredWorkout
        do {
            workout = try choice.template.instantiate(values: choice.values)
        } catch {
            throw PlanGeneratorError.workoutTemplate(error)
        }
        let resolution = StepTargetResolver.resolve(
            workout,
            on: run.day,
            athlete: request.athlete,
            raceTarget: request.targetRace.specificPhaseTarget,
            raceTargetFraction: raceTargetFraction
        )
        let resolved = resolution.workout
        // Only a hard work step is meant to be at the phase's pace (or any zone pace); the other steps are not reported.
        let unresolvedReason = resolution.unresolved.first { step in
            guard choice.template.blocks.indices.contains(step.blockIndex) else { return false }
            let block = choice.template.blocks[step.blockIndex]
            return block.steps.indices.contains(step.stepIndex) && block.steps[step.stepIndex].isHardWork(in: block)
        }?.reason
        return .run(FittedRun(
            workout: resolved,
            planned: PlannedActivity(workoutID: resolved.id, date: run.day, cycleID: cycleID),
            session: PlannedIntensityClassifier().session(on: run.day, for: resolved, athlete: request.athlete),
            templateID: choice.template.id,
            templateName: choice.template.name,
            seconds: choice.seconds,
            unresolvedReason: unresolvedReason
        ))
    }

    /// The profile of a run. A hard run takes the phase's hard profiles (interval, tempo and hill
    /// sessions) in turn, the first hard run of the micro the profile at the micro's `position` in its
    /// phase, the next the following one, and so on round again, so a micro with a single hard run
    /// gets each profile in turn across the phase; a phase without any gives the run type's session
    /// type alone. Any other
    /// run takes the phase's profile for its session type, else the session type alone.
    private func profile(for run: DayAssignment, eased: Bool, hardIndex: Int, position: Int, phase: CyclePhase) -> SessionProfile {
        let sessionType = (eased ? RunType.easy : run.runType).sessionType
        let profiles = request.paradigm.sessionProfiles[phase] ?? []
        if Self.hardTypes.contains(run.runType) && !eased {
            let hard = profiles.filter { Self.hardSessionTypes.contains($0.sessionType) }
            if !hard.isEmpty { return hard[(hardIndex + position) % hard.count] }
        }
        return profiles.first { $0.sessionType == sessionType } ?? SessionProfile(sessionType: sessionType)
    }

    private static let hardSessionTypes: Set<SessionType> = [.interval, .tempo, .hillRepeats]
    private static let hardTypes: Set<RunType> = [.interval, .threshold]
    private static let easedTypes: Set<RunType> = [.interval, .threshold, .long]

    /// Steps 1 and 2: the macro that fits the lead time and the micros laid out back from race day.
    private func layout(
        levers: PlanLevers, calendar: Calendar, compromises: inout [PlanCompromise]
    ) throws -> (micros: [Microcycle], macro: MacroTemplate) {
        let startDay = calendar.startOfDay(for: request.start)
        let raceDay = calendar.startOfDay(for: request.targetRace.date)
        guard raceDay >= startDay else { throw PlanGeneratorError.noLayout }
        let leadTimeDays = (calendar.dateComponents([.day], from: startDay, to: raceDay).day ?? 0) + 1
        let adjustment: LeadTimeAdjustment
        do {
            adjustment = try request.leadTimeCompromiser.adjust(
                request.macro, paradigm: request.paradigm, leadTimeDays: leadTimeDays,
                microLengthDays: request.meso.microLengthDays, preferences: request.preferences
            )
        } catch let error as LeadTimeError {
            throw PlanGeneratorError.leadTime(error)
        }
        for compromise in adjustment.compromises {
            compromises.append(.leadTime(compromise))
            if compromise.overriddenPreference == .includeConditioning {
                compromises.append(.overriddenPreference(.includeConditioning))
            }
        }
        let laidOut = request.keyRaceLayout.microcycles(
            from: startDay, to: request.targetRace, races: [request.targetRace] + request.otherRaces,
            macro: adjustment.macro, meso: request.meso, athlete: request.athlete
        )
        guard !laidOut.micros.isEmpty else { throw PlanGeneratorError.noLayout }
        let micros = laidOut.micros.map { micro in
            levers.downWeeks.contains(micro.dateRange.lowerBound)
                ? Microcycle(dateRange: micro.dateRange, phase: micro.phase, loadRole: .recovery, mesoBlockIndex: micro.mesoBlockIndex)
                : micro
        }
        return (micros, adjustment.macro)
    }

    /// A volume as a duration in seconds: a duration as it is, a distance at the easy pace (zone 2) of
    /// the athlete's pace model.
    private func durationSeconds(of target: VolumeTarget) throws -> TimeInterval {
        switch target.measure {
        case .durationSeconds: target.amount
        case .distanceMeters: request.athlete.paceModel.duration(forMeters: target.amount, atZone: 2)
        case .trimp: throw PlanGeneratorError.unsupportedVolumeMeasure(.trimp)
        }
    }

    /// Step 4: the volume of each micro, the peak capped by the athlete's weekly maximum.
    private func volumeTargets(for micros: [Microcycle], curve: VolumeCurveBuilder) throws -> [MicroVolumeTarget] {
        for measure in [request.startingVolume.measure, request.peakVolume.measure] where measure == .trimp {
            throw PlanGeneratorError.unsupportedVolumeMeasure(measure)
        }
        var starting = request.startingVolume
        var peak = request.peakVolume
        if let limit = request.preferences.maxWeeklyVolume[.running] {
            guard limit.measure == peak.measure else { throw PlanGeneratorError.volumeCurve(.mismatchedMeasure) }
            if limit.amount < peak.amount { peak = limit }
            if peak.amount < starting.amount { starting = peak }
        }
        do {
            return try curve.targets(for: micros, starting: starting, peak: peak)
        } catch let error as VolumeCurveError {
            throw PlanGeneratorError.volumeCurve(error)
        }
    }

    /// Step 8: the series with the plan in it, through race day.
    private func projectedMetrics(
        plans: [PlannedActivity], workouts: [StructuredWorkout], races: [Race], through raceDay: Date, calendar: Calendar, today: Date
    ) -> [FitnessMetrics] {
        var days = DailyLoadSeries().days(
            activities: request.activities,
            plans: plans,
            workouts: workouts,
            races: races,
            estimator: TRIMPPlanEstimator(),
            calculators: [ExponentialTRIMPCalculator(), ImportedLoadCalculator(), DurationRPECalculator()],
            athlete: request.athlete,
            today: today
        )
        while let last = days.last?.day, last < raceDay, let next = calendar.date(byAdding: .day, value: 1, to: last) {
            days.append(DayLoad(day: next, load: 0, isProjected: true))
        }
        return FitnessMetricsCalculator().metrics(for: days, parameters: LoadModelParameters(), seed: nil)
    }
}

private extension UnresolvedReason {
    /// Whether the reason is about the template (its zone does not hold the phase pace) and not about the plan
    /// (no race target, no zone settings): the second kind is the same for every template.
    var dependsOnTemplate: Bool {
        if case .paceOutsideZone = self { true } else { false }
    }
}
