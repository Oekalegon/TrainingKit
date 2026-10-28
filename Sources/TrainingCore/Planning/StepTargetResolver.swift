import Foundation

/// Gives the steps of a workout concrete targets for one athlete on one date (MVP5-122).
///
/// A pure function of its inputs; it reads no clock and stores nothing. The caller stores the
/// returned workout in the plan, so a workout already sent to a watch does not change when the zones
/// are edited later; re-planning resolves again.
///
/// The rules, per step:
/// - A `.heartRateZone(n)` target becomes `.heartRateRange` with the bpm bounds of zone `n` from the
///   zone settings in effect on the date (``AthleteProfile/heartRateZoneSettings(asOf:)``). Its
///   ``HeartRateZoneModel/intensityRatio(for:)`` is the zone's midpoint ratio, so
///   ``TRIMPPlanEstimator`` and ``WorkoutDurationEstimator`` read the resolved step as the same zone.
///   The ``WorkoutStep/companionTarget`` is the zone's pace, see below.
/// - On a `.work` step with a zone, when the phase gives a race-target fraction and the race target
///   is a pace, the companion is the phase pace instead, provided it falls in the zone's pace range.
///   If it does not, the step keeps the zone's pace and is reported as
///   ``UnresolvedReason/paceOutsideZone(zone:paceZone:)``: the template does not suit the phase.
/// - A `.work` step with no target and a fraction gets `.pace` as its target.
/// - A `.pace`, `.power`, `.heartRateRange` or `.rpe` target is kept as it is, and so is a step
///   with no target that is not a work step.
///
/// A fraction scales *speed*: pace is the race pace divided by the fraction, so 1.05 is 5 % faster
/// than race pace and 0.9 is slower.
///
/// Resolving keeps a heart-rate range it wrote earlier, so after the zones change a re-plan must
/// resolve the template's workout again, not a stored resolved one.
public enum StepTargetResolver {
    /// Half-width of the pace range written for a fraction of the race pace, as a fraction of that
    /// pace (0.02 is plus and minus 2 %).
    public static let fractionPaceTolerance = 0.02

    /// Resolves the targets of `workout`.
    ///
    /// - Parameters:
    ///   - workout: The workout to resolve; not modified.
    ///   - date: The day the workout is done; picks the zone settings and pace model in effect.
    ///   - athlete: Supplies the date-effective heart-rate zones and pace model.
    ///   - raceTarget: The race's ``SpecificPhaseTarget``, or `nil` for none. Only `.pace` can be
    ///     turned into a pace.
    ///   - raceTargetFraction: The phase's ``SessionProfile/raceTargetFraction``, or `nil` for none
    ///     (then the race target is not consulted). A value that is not finite and above zero counts
    ///     as `nil`.
    /// - Returns: The workout with resolved targets, and the steps that could not be fully resolved.
    public static func resolve(
        _ workout: StructuredWorkout,
        on date: Date,
        athlete: AthleteProfile,
        raceTarget: SpecificPhaseTarget?,
        raceTargetFraction: Double?
    ) -> StepTargetResolution {
        let zoneModel = athlete.heartRateZoneSettings(asOf: date).map { HeartRateZoneModel(settings: $0) }
        let paceModel = athlete.paceModel(asOf: date)
        let fraction = raceTargetFraction.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

        // The phase pace is the same for every step, so work it out once.
        var phasePace: Double?
        var phaseProblem: UnresolvedReason?
        if let fraction {
            switch raceTarget {
            case .pace(let seconds) where seconds.isFinite && seconds > 0:
                phasePace = seconds / fraction
            case .none:
                phaseProblem = .noRaceTarget
            default:
                phaseProblem = .unsupportedRaceTarget
            }
        }

        var resolved = workout
        var unresolved: [UnresolvedStep] = []
        for (blockIndex, block) in workout.blocks.enumerated() {
            for (stepIndex, step) in block.steps.enumerated() {
                var step = step
                var reason: UnresolvedReason?
                switch step.target {
                case .heartRateZone(let zone):
                    reason = resolveZone(zone, in: &step, zoneModel: zoneModel, paceModel: paceModel, phasePace: step.kind == .work ? phasePace : nil)
                    if reason == nil, step.kind == .work { reason = phaseProblem }
                case nil where step.kind == .work && fraction != nil:
                    if let phasePace {
                        let tolerance = phasePace * fractionPaceTolerance
                        step.target = .pace((phasePace - tolerance)...(phasePace + tolerance))
                    } else {
                        reason = phaseProblem
                    }
                default:
                    break
                }
                resolved.blocks[blockIndex].steps[stepIndex] = step
                if let reason { unresolved.append(UnresolvedStep(blockIndex: blockIndex, stepIndex: stepIndex, reason: reason)) }
            }
        }
        return StepTargetResolution(workout: resolved, unresolved: unresolved)
    }

    /// The pace range, in seconds per kilometer, of heart-rate zone `zone` in `paceModel`: the zone's
    /// own pace (threshold pace times its multiplier) with the bounds halfway to the neighbouring
    /// zones' paces. The outer zones extend by the same distance their inner neighbour does.
    /// `nil` for a zone outside 1...5. Assumes the multipliers get smaller from zone 1 to zone 5; for a
    /// table that does not, the bounds are still ordered but not meaningful.
    ///
    /// - Parameters:
    ///   - zone: The zone, 1...5.
    ///   - paceModel: The pace model to read.
    public static func paceRange(zone: Int, in paceModel: PaceModel) -> ClosedRange<Double>? {
        guard (1...5).contains(zone) else { return nil }
        func pace(_ zone: Int) -> Double { paceModel.secondsPerMeter(atZone: zone) * 1000 }
        let own = pace(zone)
        let slowerNeighbour = zone > 1 ? pace(zone - 1) : nil
        let fasterNeighbour = zone < 5 ? pace(zone + 1) : nil
        let slowGap = slowerNeighbour.map { $0 - own } ?? fasterNeighbour.map { own - $0 } ?? 0
        let fastGap = fasterNeighbour.map { own - $0 } ?? slowerNeighbour.map { $0 - own } ?? 0
        let bounds = [own - fastGap / 2, own + slowGap / 2]
        return bounds.min()!...bounds.max()!
    }

    /// The zone (1...5) whose ``paceRange(zone:in:)`` contains `pace`, the slower zone at a shared
    /// boundary, or `nil` when it is faster or slower than every zone.
    static func zone(forPace pace: Double, in paceModel: PaceModel) -> Int? {
        (1...5).first { paceRange(zone: $0, in: paceModel)?.contains(pace) == true }
    }

    private static func resolveZone(
        _ zone: Int, in step: inout WorkoutStep, zoneModel: HeartRateZoneModel?, paceModel: PaceModel, phasePace: Double?
    ) -> UnresolvedReason? {
        guard let zoneModel else { return .noHeartRateZones }
        guard let bpm = zoneModel.zoneBPMRange(zone), let zonePace = paceRange(zone: zone, in: paceModel) else {
            return .zoneUnavailable(zone)
        }
        step.target = .heartRateRange(bpm.lowerBound, bpm.upperBound)
        step.companionTarget = .pace(zonePace)
        guard let phasePace else { return nil }
        guard zonePace.contains(phasePace) else {
            return .paceOutsideZone(zone: zone, paceZone: Self.zone(forPace: phasePace, in: paceModel))
        }
        let tolerance = phasePace * fractionPaceTolerance
        step.companionTarget = .pace((phasePace - tolerance)...(phasePace + tolerance))
        return nil
    }
}
