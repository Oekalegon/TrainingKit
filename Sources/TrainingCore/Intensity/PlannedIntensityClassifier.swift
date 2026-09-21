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

    /// Classifies `workout` for `athlete`.
    ///
    /// A workout with no duration is ``IntensityCategory/veryLow`` with ``IntensityAssessment/Confidence/low``
    /// confidence. Confidence is ``IntensityAssessment/Confidence/high`` only when every step's
    /// zone came from an explicit, resolvable target; a step with no target, a power target, or a
    /// heart-rate range without recorded zone settings falls back to a default and lowers it to
    /// ``IntensityAssessment/Confidence/medium``.
    public func assess(_ workout: StructuredWorkout, athlete: AthleteProfile) -> IntensityAssessment {
        let zoneModel = athlete.currentHeartRateZoneSettings.map(HeartRateZoneModel.init(settings:))
        let boundaries = zoneModel.flatMap(TimeInZoneBuilder.zoneBoundaries)

        var totalSeconds: TimeInterval = 0
        var hardSeconds: TimeInterval = 0
        var moderateSeconds: TimeInterval = 0
        var aboveFirstZoneSeconds: TimeInterval = 0
        var allTargetsResolved = true

        for block in workout.blocks {
            for step in block.steps {
                let seconds = durationEstimator.duration(for: step, athlete: athlete) * Double(block.repetitions)
                guard seconds > 0 else { continue }

                let resolved = resolveZone(for: step, athlete: athlete, zoneModel: zoneModel, boundaries: boundaries)
                if !resolved.isExplicit || step.goal == .open {
                    allTargetsResolved = false
                }

                let isEdge = step.kind == .warmup || step.kind == .cooldown
                let zone = isEdge ? min(resolved.zone, 2) : resolved.zone

                totalSeconds += seconds
                if zone >= 4 {
                    hardSeconds += seconds
                } else if zone == 3 {
                    moderateSeconds += seconds
                }
                if zone >= 2 {
                    aboveFirstZoneSeconds += seconds
                }
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
