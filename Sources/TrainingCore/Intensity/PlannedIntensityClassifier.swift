import Foundation

/// Classifies a ``StructuredWorkout``'s intensity from its steps alone, with no sensor data.
///
/// Each step is resolved to a heart-rate zone from its ``IntensityTarget`` (or a default for its
/// ``StepKind`` when there is none), weighted by its duration and its block's repetitions, and
/// the resulting time in zones goes through ``IntensityClassifierParameters/category(totalSeconds:hardSeconds:moderateSeconds:aboveFirstZoneSeconds:)``.
///
/// Warm-up and cool-down steps count towards the session's duration but never towards its hard or
/// moderate time — they are capped at zone 2 — so a workout doesn't become harder because it
/// warms up briskly.
public struct PlannedIntensityClassifier: Sendable {
    /// The thresholds applied to the session's time in zones.
    public var parameters: IntensityClassifierParameters
    /// Converts step goals to durations.
    public var durationEstimator: WorkoutDurationEstimator

    /// Creates a classifier.
    public init(
        parameters: IntensityClassifierParameters = IntensityClassifierParameters(),
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator()
    ) {
        self.parameters = parameters
        self.durationEstimator = durationEstimator
    }

    /// One step of a workout with its repetitions unrolled, placed on the workout's timeline.
    struct PlannedStep: Sendable {
        /// Seconds from the start of the workout, assuming steps run back to back.
        let offset: TimeInterval
        let seconds: TimeInterval
        let kind: StepKind
        /// The zone the step's target resolves to, or the default for its kind.
        let zone: Int
        /// Whether `zone` came from an explicit, resolvable target.
        let isExplicit: Bool
        /// Whether `seconds` is fixed by the step's goal, so `offset` is reliable. Distance and
        /// open goals last however long they take, which shifts everything after them.
        let hasFixedDuration: Bool
        let isOpen: Bool

        /// Warm-up and cool-down never count as hard or moderate time.
        var isEdge: Bool { kind == .warmup || kind == .cooldown }
        /// The zone counted towards the ladder: edges are capped at zone 2.
        var countedZone: Int { isEdge ? min(zone, 2) : zone }
    }

    /// Classifies `workout` for `athlete`.
    ///
    /// A workout with no duration is ``IntensityCategory/veryLow`` with ``IntensityAssessment/Confidence/low``
    /// confidence. Confidence is ``IntensityAssessment/Confidence/high`` only when every step's
    /// zone came from an explicit, resolvable target; a step with no target, a power target, or a
    /// heart-rate range without recorded zone settings falls back to a default and lowers it to
    /// ``IntensityAssessment/Confidence/medium``.
    public func assess(_ workout: StructuredWorkout, athlete: AthleteProfile) -> IntensityAssessment {
        assess(steps: plannedSteps(workout, athlete: athlete), zone: \.countedZone)
    }

    /// The workout's steps with repetitions unrolled, in order.
    func plannedSteps(_ workout: StructuredWorkout, athlete: AthleteProfile) -> [PlannedStep] {
        let zoneModel = athlete.currentHeartRateZoneSettings.map(HeartRateZoneModel.init(settings:))
        let boundaries = zoneModel.flatMap(TimeInZoneBuilder.zoneBoundaries)

        var steps: [PlannedStep] = []
        var offset: TimeInterval = 0
        for block in workout.blocks {
            for _ in 0..<max(block.repetitions, 0) {
                for step in block.steps {
                    let seconds = durationEstimator.duration(for: step, athlete: athlete)
                    guard seconds > 0 else { continue }

                    let resolved = resolveZone(for: step, athlete: athlete, zoneModel: zoneModel, boundaries: boundaries)
                    var hasFixedDuration = false
                    if case .time = step.goal { hasFixedDuration = true }
                    steps.append(PlannedStep(
                        offset: offset,
                        seconds: seconds,
                        kind: step.kind,
                        zone: resolved.zone,
                        isExplicit: resolved.isExplicit,
                        hasFixedDuration: hasFixedDuration,
                        isOpen: step.goal == .open
                    ))
                    offset += seconds
                }
            }
        }
        return steps
    }

    /// Classifies `steps`, counting each step towards the zone `zone` returns for it.
    ///
    /// This lets a caller substitute the zone a step was actually performed in for the zone it
    /// was planned at.
    func assess(steps: [PlannedStep], zone: (PlannedStep) -> Int) -> IntensityAssessment {
        var totalSeconds: TimeInterval = 0
        var hardSeconds: TimeInterval = 0
        var moderateSeconds: TimeInterval = 0
        var aboveFirstZoneSeconds: TimeInterval = 0
        var allTargetsResolved = true

        for step in steps {
            if !step.isExplicit || step.isOpen {
                allTargetsResolved = false
            }
            let counted = zone(step)
            totalSeconds += step.seconds
            if counted >= 4 {
                hardSeconds += step.seconds
            } else if counted == 3 {
                moderateSeconds += step.seconds
            }
            if counted >= 2 {
                aboveFirstZoneSeconds += step.seconds
            }
        }

        guard totalSeconds > 0 else {
            return IntensityAssessment(category: .veryLow, source: .planned, confidence: .low, hardSeconds: 0, moderateSeconds: 0)
        }

        let category = parameters.category(
            totalSeconds: totalSeconds,
            hardSeconds: hardSeconds,
            moderateSeconds: moderateSeconds,
            aboveFirstZoneSeconds: aboveFirstZoneSeconds
        )
        return IntensityAssessment(
            category: category,
            source: .planned,
            confidence: allTargetsResolved ? .high : .medium,
            hardSeconds: hardSeconds,
            moderateSeconds: moderateSeconds
        )
    }

    private struct ResolvedZone {
        let zone: Int
        let isExplicit: Bool
    }

    private func resolveZone(
        for step: WorkoutStep,
        athlete: AthleteProfile,
        zoneModel: HeartRateZoneModel?,
        boundaries: [Double]?
    ) -> ResolvedZone {
        let fallback = ResolvedZone(zone: Self.defaultZone(for: step.kind), isExplicit: false)
        guard let target = step.target else { return fallback }

        switch target {
        case .heartRateZone(let zone):
            return ResolvedZone(zone: min(max(zone, 1), 5), isExplicit: true)
        case .heartRateRange(let low, let high):
            guard let zoneModel, let boundaries else { return fallback }
            let ratio = zoneModel.deltaHRRatio(for: (low + high) / 2)
            return ResolvedZone(zone: TimeInZoneBuilder.zone(for: ratio, boundaries: boundaries), isExplicit: true)
        case .pace(let range):
            let midpoint = (range.lowerBound + range.upperBound) / 2
            return ResolvedZone(zone: Self.nearestZone(toPaceSecondsPerKilometer: midpoint, paceModel: athlete.paceModel), isExplicit: true)
        case .rpe(let rpe):
            return ResolvedZone(zone: Self.zone(forRPE: rpe), isExplicit: true)
        case .power:
            return fallback
        }
    }

    /// The zone assumed for a step with no usable target: work is tempo effort, everything else easy.
    private static func defaultZone(for kind: StepKind) -> Int {
        kind == .work ? 3 : 1
    }

    /// The zone whose pace, per ``PaceModel``, is closest to `secondsPerKilometer`.
    private static func nearestZone(toPaceSecondsPerKilometer secondsPerKilometer: Double, paceModel: PaceModel) -> Int {
        (1...5).min { lhs, rhs in
            abs(paceModel.secondsPerMeter(atZone: lhs) * 1000 - secondsPerKilometer)
                < abs(paceModel.secondsPerMeter(atZone: rhs) * 1000 - secondsPerKilometer)
        } ?? 3
    }

    /// Borg CR10 effort mapped to a zone: 1–2 easy, 3 aerobic, 4–5 tempo, 6–7 threshold, 8+ maximal.
    private static func zone(forRPE rpe: Int) -> Int {
        switch rpe {
        case ...2: return 1
        case 3: return 2
        case 4...5: return 3
        case 6...7: return 4
        default: return 5
        }
    }
}
