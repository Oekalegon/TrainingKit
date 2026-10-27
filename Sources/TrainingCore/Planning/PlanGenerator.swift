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
///    -20, and the micros then end fresher than that.
/// 5. ``DayAssigner`` places the micro's hard sessions, long runs and easy runs on the athlete's days
///    and day parts, with the spacing of earlier micros passed as `preceding`. Nothing is placed on
///    the day of a race. A session it cannot place is ``PlanCompromise/unplacedSession(microStart:_:)``.
/// 6. Each run gets a ``SessionProfile`` (the paradigm's profile for the micro's phase and the run's
///    session type, else one with the session type only; a micro's hard runs take the phase's hard
///    profiles in turn, so a structural micro with two gets a fast and an endurance quality session). ``SessionProfile/progressedWorkLength(microIndex:of:)``
///    steps the work length across the phase, and ``TemplateFitter`` picks and sizes a template for an
///    equal share of the micro's duration, with the previous micro's templates (only that one) for rotation. No
///    template is ``PlanCompromise/missingTemplate(microStart:_:)`` and the run is left out.
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

        var planned: [PlannedActivity] = []
        var workouts: [StructuredWorkout] = []
        var planSessions: [PlanSession] = []
        var overWeeklyLimit = false
        var hardDates: [Date] = []
        var longDates: [Date] = []
        var previousTemplates: [UUID] = []
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
                raceDays: raceDays,
                targetRace: request.targetRace,
                calendar: calendar
            )
            let phaseMicros = micros.indices.filter { micros[$0].phase == micro.phase }
            let position = phaseMicros.firstIndex(of: index) ?? 0

            func build(_ seconds: TimeInterval) throws -> MicroBuild {
                try buildMicro(
                    assignment, micro: micro, cycleID: microCycles[index].id, seconds: seconds, position: position,
                    phaseCount: phaseMicros.count, previous: previousTemplates, levers: levers
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
            if let aim = sizingAim(for: micro, raceDays: raceDays, calendar: calendar) {
                let top = try build(ceilingSeconds)
                if let topMetric = endTSB(of: top, on: aim.day), !topMetric.isWarmingUp {
                    var chosen = (scale: 1.0, build: top)
                    if topMetric.tsb < aim.tsb {
                        // Too tired at the ceiling: the largest volume that still ends at the aim, found by
                        // bisection; when no volume reaches it, the lightest one tried.
                        var (low, high) = (0.0, 1.0)
                        var reached: (scale: Double, build: MicroBuild)?
                        var lightest = chosen
                        for _ in 0..<Self.sizingSteps {
                            let scale = (low + high) / 2
                            let probe = try build(ceilingSeconds * scale)
                            guard let metric = endTSB(of: probe, on: aim.day) else { break }
                            if scale < lightest.scale { lightest = (scale, probe) }
                            if metric.tsb < aim.tsb { high = scale } else { low = scale; reached = (scale, probe) }
                            if abs(metric.tsb - aim.tsb) < Self.sizingTolerance { reached = (scale, probe); break }
                        }
                        chosen = reached ?? lightest
                    }
                    built = leverScale == 1 ? chosen.build : try build(ceilingSeconds * chosen.scale * leverScale)
                } else {
                    // Still warming up (no history to aim from): the curve's own volume.
                    built = try build(curveSeconds)
                }
            } else {
                built = try build(curveSeconds)
            }

            compromises += assignment.dropped.map { .unplacedSession(microStart: microStart, $0) }
            compromises += built.compromises
            workouts += built.workouts
            planned += built.planned
            planSessions += built.sessions
            hardDates += built.hardDays
            longDates += built.longDays
            previousTemplates = built.templates
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
    private func sizingAim(for micro: Microcycle, raceDays: [Date], calendar: Calendar) -> (day: Date, tsb: Double)? {
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
        return zone.midpoint(guardrails: guardrails).map { (day, $0) }
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
        var compromises: [PlanCompromise] = []
    }

    /// Steps 5 and 6 for one micro: the runs of `assignment` fitted to an equal share of `seconds`.
    private func buildMicro(
        _ assignment: DayAssignmentResult, micro: Microcycle, cycleID: UUID, seconds: TimeInterval, position: Int,
        phaseCount: Int, previous: [UUID], levers: PlanLevers
    ) throws -> MicroBuild {
        var built = MicroBuild()
        let share = seconds / Double(max(assignment.assignments.count, 1))
        var hardIndex = 0
        for run in assignment.assignments where !levers.droppedDays.contains(run.day) {
            let eased = levers.easedDays.contains(run.day) && Self.easedTypes.contains(run.runType)
            let fitted = try fitRun(
                run, eased: eased, hardIndex: hardIndex, micro: micro, position: position, phaseCount: phaseCount,
                share: share, previous: previous, cycleID: cycleID
            )
            if Self.hardTypes.contains(run.runType) && !eased { hardIndex += 1 }
            guard case .run(let result) = fitted else {
                if case .missing(let profile) = fitted { built.compromises.append(.missingTemplate(microStart: micro.dateRange.lowerBound, profile)) }
                continue
            }
            built.workouts.append(result.workout)
            built.planned.append(result.planned)
            built.sessions.append(result.session)
            built.templates.append(result.templateID)
            built.fittedSeconds += result.seconds
            if Self.hardTypes.contains(run.runType) && !eased { built.hardDays.append(run.day) }
            if run.runType == .long && !eased { built.longDays.append(run.day) }
        }
        return built
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
        let seconds: TimeInterval
    }

    /// Steps 6 and 7 for one run: profile, template fit, instantiation, step targets, and the
    /// planned workout and session that come of it.
    private func fitRun(
        _ run: DayAssignment, eased: Bool, hardIndex: Int, micro: Microcycle, position: Int, phaseCount: Int,
        share: TimeInterval, previous: [UUID], cycleID: UUID
    ) throws -> RunFit {
        let profile = profile(for: run, eased: eased, hardIndex: hardIndex, position: position, phase: micro.phase)
        let fit = TemplateFitter.fit(
            profile: profile,
            targetSeconds: share,
            templates: request.templates,
            previous: previous,
            workLength: profile.progressedWorkLength(microIndex: position, of: phaseCount),
            athlete: request.athlete
        )
        guard case .fit(let choice) = fit else { return .missing(profile) }
        let workout: StructuredWorkout
        do {
            workout = try choice.template.instantiate(values: choice.values)
        } catch {
            throw PlanGeneratorError.workoutTemplate(error)
        }
        let resolved = StepTargetResolver.resolve(
            workout,
            on: run.day,
            athlete: request.athlete,
            raceTarget: request.targetRace.specificPhaseTarget,
            raceTargetFraction: profile.progressedRaceTargetFraction(microIndex: position, of: phaseCount)
        ).workout
        return .run(FittedRun(
            workout: resolved,
            planned: PlannedActivity(workoutID: resolved.id, date: run.day, cycleID: cycleID),
            session: PlannedIntensityClassifier().session(on: run.day, for: resolved, athlete: request.athlete),
            templateID: choice.template.id,
            seconds: choice.seconds
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
