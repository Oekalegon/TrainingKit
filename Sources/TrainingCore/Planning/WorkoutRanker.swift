import Foundation

/// Ranks the workouts an athlete could put on a day of a plan (MVP5-155): every running template, filled in
/// with every combination of parameter values on the steps of ``ParameterGrid``, best first.
///
/// A pure function of the plan, the history and the templates; no new rule is involved, it reuses
/// ``PlanEvaluator``, ``FitnessMetricsCalculator`` and the recovery days of the templates.
///
/// **What is offered.** For each running, non-archived template, each parameter takes the values of its range on
/// the grid (a parameter without a range keeps its default). A workout stays when it is near the target:
/// - when the athlete replaces a workout, the target is that workout's load (its
///   ``PlannedActivity/expectedLoadOverride``, else the estimate), so an easy run and an interval session of
///   about the same load compete;
/// - when the athlete adds one, the target is the time the micro's volume has left.
///
/// "Near" is within ``targetMargin`` of the target. With no target (adding without a micro volume) every workout stays.
///
/// **How it ranks.** Lexicographic, like ``TemplateFitter``, with no weights:
/// 1. the number of problems the workout brings: a risk the plan did not have (the evaluator's rules on the plan with
///    the workout in it) and recovery days short of what the template wants (see ``WorkoutRankReason``);
/// 2. whether the micro's phase asks for the session type at all (a mismatch ranks below, but stays in the list);
/// 3. the distance of the TSB at the end of the micro from the aim of its role (the midpoint of the zone: training for a
///    build micro, recovery for a recovery micro, race for a taper micro);
/// 4. the distance of the micro's planned time from its volume;
/// 5. the distance from the target;
/// 6. the template's name.
///
/// A phase-intensity step (``IntensityTarget/phaseIntensity``) is not resolved: the plan's phase pace is not an input,
/// so such a workout is estimated with the step as it is.
public enum WorkoutRanker {
    /// How far from the target a workout may be and stay in the list, as a fraction of the target (0.3 is 30 %).
    public static let targetMargin = 0.3

    /// Ranks the workouts for `day`.
    ///
    /// - Parameters:
    ///   - day: The day to put the workout on; its start of day in the athlete's time zone counts.
    ///   - replacing: The planned workout the new one replaces, if any; it is in `plan`.
    ///   - plan: The planned activities of the plan, including `replacing`.
    ///   - workouts: The workouts `plan` refers to.
    ///   - templates: The templates to offer, the athlete's own as well as the built-in ones.
    ///   - cycles: The plan's cycles, for the micro of the day (its phase, role and dates).
    ///   - activities: The past activities, for the series.
    ///   - races: The races, for the series and the race-day rule.
    ///   - athlete: The athlete the workouts are timed and scored for.
    ///   - paradigm: The paradigm whose rules apply; defaults to `nil`.
    ///   - targetRace: The race the plan builds towards; defaults to `nil`.
    ///   - guardrails: The thresholds; defaults to ``PlanGuardrails``'s defaults.
    ///   - microSeconds: The volume of the day's micro, in seconds, from the plan's volume curve; defaults to `nil`,
    ///     which leaves volume out of the ranking and the target of an added workout open.
    ///   - today: The boundary between past and projected days.
    /// - Returns: The workouts, best first; empty when no template can be filled in.
    public static func rank(
        day: Date,
        replacing: PlannedActivity? = nil,
        plan: [PlannedActivity],
        workouts: [StructuredWorkout],
        templates: [WorkoutTemplate],
        cycles: [TrainingCycle],
        activities: [Activity],
        races: [Race],
        athlete: AthleteProfile,
        paradigm: TrainingParadigm? = nil,
        targetRace: Race? = nil,
        guardrails: PlanGuardrails = PlanGuardrails(),
        microSeconds: TimeInterval? = nil,
        today: Date
    ) -> [RankedWorkout] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let day = calendar.startOfDay(for: day)
        let resolved = paradigm?.resolved(for: targetRace)
        let appliedGuardrails = resolved.map { $0.guardrailOverrides.applied(to: guardrails) } ?? guardrails
        let micro = cycles.first {
            $0.level == .micro && calendar.startOfDay(for: $0.dateRange.lowerBound) <= day && day <= calendar.startOfDay(for: $0.dateRange.upperBound)
        }
        let evaluationRaces = races.map { race -> Race in
            var race = race
            race.date = calendar.startOfDay(for: race.date)
            return race
        }
        let durations = WorkoutDurationEstimator()
        let estimator = TRIMPPlanEstimator()
        let classifier = PlannedIntensityClassifier()
        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func sessions(of planned: [PlannedActivity]) -> [PlanSession] {
            planned.compactMap { item in
                workoutsByID[item.workoutID].map { classifier.session(on: calendar.startOfDay(for: item.date), for: $0, athlete: athlete) }
            }
        }
        func days(of planned: [PlannedActivity], workouts: [StructuredWorkout]) -> [DayLoad] {
            DailyLoadSeries().days(
                activities: activities, plans: planned, workouts: workouts, races: evaluationRaces, estimator: estimator,
                calculators: [ExponentialTRIMPCalculator(), ImportedLoadCalculator(), DurationRPECalculator()], athlete: athlete, today: today
            )
        }
        func risks(metrics: [FitnessMetrics], sessions: [PlanSession]) -> [PlanFinding] {
            PlanEvaluator().evaluate(
                metrics, races: evaluationRaces, cycles: cycles, guardrails: guardrails, sessions: sessions, paradigm: paradigm, targetRace: targetRace
            ).findings.filter { $0.severity == .risk }
        }
        struct FindingKey: Hashable {
            let rule: PlanRule
            let day: Date
        }
        func metrics(of days: [DayLoad]) -> [FitnessMetrics] {
            FitnessMetricsCalculator().metrics(for: days, parameters: LoadModelParameters(), seed: nil)
        }
        let existing = Set(risks(metrics: metrics(of: days(of: plan, workouts: workouts)), sessions: sessions(of: plan)).map { FindingKey(rule: $0.rule, day: $0.day) })

        let others = plan.filter { $0.id != replacing?.id }
        // The series without the new workout, once: a workout only adds its load on its day (a day before today feeds nothing).
        let baseDays = days(of: others, workouts: workouts)
        let baseSessions = sessions(of: others)
        let feedsSeries = day >= calendar.startOfDay(for: today)
        func isInMicro(_ date: Date) -> Bool {
            guard let micro else { return false }
            let start = calendar.startOfDay(for: date)
            return calendar.startOfDay(for: micro.dateRange.lowerBound) <= start && start <= calendar.startOfDay(for: micro.dateRange.upperBound)
        }
        let plannedSeconds = others.filter { isInMicro($0.date) }.reduce(0.0) { total, item in
            total + (workoutsByID[item.workoutID].map { durations.duration(for: $0, athlete: athlete) } ?? 0)
        }

        // The target: the load of the replaced workout, else the time left in the micro.
        enum Target {
            case load(Double)
            case seconds(TimeInterval)
        }
        var target: Target?
        if let replacing {
            if let load = replacing.expectedLoadOverride ?? workoutsByID[replacing.workoutID].map({ estimator.estimatedLoad(for: $0, athlete: athlete).value }) {
                target = .load(load)
            }
        } else if let microSeconds, microSeconds - plannedSeconds > 0 {
            target = .seconds(microSeconds - plannedSeconds)
        }

        // The neighbours that want days free around them.
        let defaultAfter = resolved?.minDaysBetweenHardSessions.flatMap { $0 > 0 ? $0 : nil }
        let demanding: [Date] = resolved.map { resolved in
            others.compactMap { item -> Date? in
                guard let workout = workoutsByID[item.workoutID] else { return nil }
                let session = classifier.session(on: calendar.startOfDay(for: item.date), for: workout, athlete: athlete)
                return resolved.isHardForSpacing(session) ? session.day : nil
            }
        } ?? []
        func daysBetween(_ start: Date, _ end: Date) -> Int { calendar.dateComponents([.day], from: start, to: end).day ?? Int.max }

        let profileTypes: Set<SessionType>? = micro.flatMap { micro in
            resolved?.sessionProfiles[micro.phase].map { Set($0.map(\.sessionType)) }
        }.flatMap { $0.isEmpty ? nil : $0 }
        let aim: Double? = micro?.loadRole.flatMap { role -> Double? in
            switch role {
            case .build: TSBZone.training.midpoint(guardrails: appliedGuardrails)
            case .recovery: TSBZone.recovery.midpoint(guardrails: appliedGuardrails)
            case .taper, .race: TSBZone.race.midpoint(guardrails: appliedGuardrails)
            }
        }
        let endDay = micro.map { calendar.startOfDay(for: $0.dateRange.upperBound) }

        struct Scored {
            let ranked: RankedWorkout
            let problems: Int
            let outsidePhase: Bool
            let tsbDistance: Double
            let volumeDistance: Double
            let targetDistance: Double
        }
        var scored: [Scored] = []
        for template in templates where template.sport == .running && !template.isArchived {
            let choices = template.parameters.map { parameter -> (key: String, values: [Double]) in
                guard let range = parameter.range else { return (parameter.key, [parameter.defaultValue]) }
                return (parameter.key, ParameterGrid.values(in: range, unit: parameter.unit))
            }
            var combinations: [[String: Double]] = [[:]]
            for choice in choices {
                combinations = combinations.flatMap { partial in choice.values.map { partial.merging([choice.key: $0]) { _, new in new } } }
            }
            for values in combinations {
                guard let workout = try? template.instantiate(values: values) else { continue }
                let seconds = durations.duration(for: workout, athlete: athlete)
                let load = estimator.estimatedLoad(for: workout, athlete: athlete).value
                var targetDistance = 0.0
                switch target {
                case .load(let wanted): targetDistance = abs(load - wanted) / max(wanted, 1)
                case .seconds(let wanted): targetDistance = abs(seconds - wanted) / max(wanted, 1)
                case nil: break
                }
                guard targetDistance <= targetMargin else { continue }

                var withDays = baseDays
                if feedsSeries, let index = withDays.firstIndex(where: { $0.day == day }) {
                    withDays[index] = DayLoad(day: day, load: withDays[index].load + load, isProjected: withDays[index].isProjected)
                }
                let resultMetrics = metrics(of: withDays)
                let found = risks(metrics: resultMetrics, sessions: baseSessions + [classifier.session(on: day, for: workout, athlete: athlete)])
                var reasons: [WorkoutRankReason] = found
                    .filter { !existing.contains(FindingKey(rule: $0.rule, day: $0.day)) }
                    .map { .addsRisk(rule: $0.rule, day: $0.day) }

                if let resolved, let own = template.effectiveRecoveryDays(defaultAfter: defaultAfter, longRunsNeedRecovery: resolved.spacesLongRunsAsHard) {
                    var worst: (needed: Int, available: Int)?
                    for date in demanding {
                        let earlier = date <= day
                        let needed = earlier ? (defaultAfter ?? 0) + own.before : own.after
                        let available = earlier ? daysBetween(date, day) : daysBetween(day, date)
                        guard available < needed, worst.map({ needed - available > $0.needed - $0.available }) ?? true else { continue }
                        worst = (needed, available)
                    }
                    if let worst { reasons.append(.recoveryDaysShort(neededDays: worst.needed, availableDays: worst.available)) }
                }
                let problems = reasons.count

                var outsidePhase = false
                if let profileTypes, let micro, workout.sessionType.map({ !profileTypes.contains($0) }) ?? true {
                    outsidePhase = true
                    reasons.append(.notAskedInPhase(micro.phase))
                }

                let withWorkout = micro == nil ? nil : plannedSeconds + seconds
                var volumeDistance = 0.0
                if let withWorkout, let microSeconds {
                    volumeDistance = abs(withWorkout - microSeconds)
                    if withWorkout > microSeconds + 1 { reasons.append(.aboveMicroVolume(by: withWorkout - microSeconds)) }
                }
                let endTSB = endDay.flatMap { end in resultMetrics.first { $0.day == end }?.tsb }
                var tsbDistance = 0.0
                if let endTSB, let aim { tsbDistance = abs(endTSB - aim) }

                scored.append(Scored(
                    ranked: RankedWorkout(
                        template: template, values: values, workout: workout, seconds: seconds, load: load,
                        endOfMicroTSB: endTSB, microSeconds: withWorkout, reasons: reasons
                    ),
                    problems: problems, outsidePhase: outsidePhase, tsbDistance: tsbDistance,
                    volumeDistance: volumeDistance, targetDistance: targetDistance
                ))
            }
        }
        return scored.sorted { lhs, rhs in
            if lhs.problems != rhs.problems { return lhs.problems < rhs.problems }
            if lhs.outsidePhase != rhs.outsidePhase { return !lhs.outsidePhase }
            if abs(lhs.tsbDistance - rhs.tsbDistance) > 1e-9 { return lhs.tsbDistance < rhs.tsbDistance }
            if abs(lhs.volumeDistance - rhs.volumeDistance) > 1e-9 { return lhs.volumeDistance < rhs.volumeDistance }
            if abs(lhs.targetDistance - rhs.targetDistance) > 1e-9 { return lhs.targetDistance < rhs.targetDistance }
            if lhs.ranked.template.name != rhs.ranked.template.name { return lhs.ranked.template.name < rhs.ranked.template.name }
            return lhs.ranked.seconds < rhs.ranked.seconds
        }.map(\.ranked)
    }
}
