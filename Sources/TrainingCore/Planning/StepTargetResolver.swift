import Foundation

/// Gives the steps of a workout concrete targets for one athlete on one date (MVP5-122).
///
/// A pure function of its inputs; it reads no clock and stores nothing. The caller stores the
/// returned workout in the plan.
///
/// A heart-rate target stays a zone target (MVP5-148): a position in the athlete's zones such as
/// `3.0...3.4` (``IntensityTarget/heartRateZoneRange(_:)``), or a whole zone, which an athlete reads more
/// easily than bpm. The bpm is worked out only when the workout is sent or run, by
/// ``resolveBPM(_:on:athlete:)``, with the zone settings in effect on that day.
///
/// The rules, per step:
/// - A `.heartRateZone(n)` or `.heartRateZoneRange` target is kept. The step is checked against the zone
///   settings in effect on the date (``AthleteProfile/heartRateZoneSettings(asOf:)``): without them, or
///   when a zone has no bpm range under the athlete's zone method, it is reported
///   (``UnresolvedReason/noHeartRateZones``, ``UnresolvedReason/zoneUnavailable(_:)``). The
///   ``WorkoutStep/companionTarget`` is the pace of the zones the target spans, see below.
/// - On a `.work` step with a zone, when the phase gives a race-target fraction and the race target
///   is a pace, the companion is the phase pace instead, provided it falls in the pace range of the
///   target's zones. If it does not, the step keeps the zone's pace and is reported as
///   ``UnresolvedReason/paceOutsideZone(zone:paceZone:)``: the template does not suit the phase.
/// - A ``IntensityTarget/phaseIntensity`` step (MVP5-153) is the intensity of the phase wherever the race is: with
///   the phase pace it becomes the zone positions that pace sits at in the pace model (so 86 % of a marathon pace
///   is an easy zone and 86 % of a 5k pace a threshold one), with the pace as the companion; a pace outside every
///   zone is clamped to the nearest edge and reported as ``UnresolvedReason/paceOutsideZone(zone:paceZone:)``;
///   without a fraction it is reported as ``UnresolvedReason/noPhaseFraction``.
/// - A `.work` step with no target and a fraction gets `.pace` as its target.
/// - A `.pace`, `.power`, `.heartRateRange` or `.rpe` target is kept as it is, and so is a step
///   with no target that is not a work step.
///
/// A fraction scales *speed*: pace is the race pace divided by the fraction, so 1.05 is 5 % faster
/// than race pace and 0.9 is slower.
///
/// Resolving keeps a companion pace it wrote earlier, so after the pace model changes a re-plan must
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
                case .heartRateZone, .heartRateZoneRange:
                    reason = resolveZone(step.target, in: &step, zoneModel: zoneModel, paceModel: paceModel, phasePace: step.kind == .work ? phasePace : nil)
                    if reason == nil, step.kind == .work { reason = phaseProblem }
                case .phaseIntensity:
                    if let phasePace {
                        reason = resolvePhaseIntensity(in: &step, phasePace: phasePace, paceModel: paceModel)
                        if reason == nil, zoneModel == nil { reason = .noHeartRateZones }
                    } else {
                        reason = fraction == nil ? .noPhaseFraction : phaseProblem
                    }
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

    /// The zone positions a heart-rate zone target spans: `n.0...(n+1).0` for a whole zone `n`, the range itself
    /// for a ``IntensityTarget/heartRateZoneRange(_:)``. `nil` for another target, a zone outside 1...5 or positions
    /// outside ``HeartRateZoneModel/zonePositions``.
    static func zonePositions(of target: IntensityTarget?) -> ClosedRange<Double>? {
        switch target {
        case .heartRateZone(let zone):
            (1...5).contains(zone) ? Double(zone)...Double(zone + 1) : nil
        case .heartRateZoneRange(let positions):
            HeartRateZoneModel.zonePositions.contains(positions.lowerBound) && HeartRateZoneModel.zonePositions.contains(positions.upperBound) ? positions : nil
        default:
            nil
        }
    }

    /// The zone a heart-rate zone target is reported under: its own zone, or the zone of the middle of its positions.
    private static func zoneNumber(of target: IntensityTarget?) -> Int {
        switch target {
        case .heartRateZone(let zone): zone
        case .heartRateZoneRange(let positions): Int(((positions.lowerBound + positions.upperBound) / 2).rounded(.down))
        default: 0
        }
    }

    /// The pace range, in seconds per kilometer, of a stretch of zone positions in `paceModel`: the zone's
    /// ``paceRange(zone:in:)`` cut at the positions, a higher position being a faster pace. A whole zone gives
    /// exactly its ``paceRange(zone:in:)``. `nil` for positions outside ``HeartRateZoneModel/zonePositions``.
    ///
    /// - Parameters:
    ///   - zonePositions: The positions, such as `3.0...3.4`.
    ///   - paceModel: The pace model to read.
    public static func paceRange(zonePositions: ClosedRange<Double>, in paceModel: PaceModel) -> ClosedRange<Double>? {
        if zonePositions.lowerBound.rounded() == zonePositions.lowerBound, zonePositions.upperBound == zonePositions.lowerBound + 1,
           let whole = paceRange(zone: Int(zonePositions.lowerBound), in: paceModel) {
            return whole
        }
        func pace(atPosition position: Double) -> Double? {
            guard HeartRateZoneModel.zonePositions.contains(position) else { return nil }
            let zone = min(Int(position.rounded(.down)), 5)
            guard let range = paceRange(zone: zone, in: paceModel) else { return nil }
            return range.upperBound - (position - Double(zone)) * (range.upperBound - range.lowerBound)
        }
        guard let slow = pace(atPosition: zonePositions.lowerBound), let fast = pace(atPosition: zonePositions.upperBound) else { return nil }
        return min(fast, slow)...max(fast, slow)
    }

    /// The zone position (1.0 to 6.0) at which `pace`, in seconds per kilometer, sits in `paceModel`: the inverse of
    /// ``paceRange(zonePositions:in:)``, a slower pace being a lower position. A pace slower than zone 1 or faster
    /// than zone 5 gives 1.0 or 6.0, and `exact` is `false`.
    ///
    /// - Parameters:
    ///   - pace: The pace, in seconds per kilometer.
    ///   - paceModel: The pace model to read.
    /// - Returns: The position, and whether the pace is inside the zones (`nil` for a pace that is not finite and above zero).
    static func zonePosition(forPace pace: Double, in paceModel: PaceModel) -> (position: Double, exact: Bool)? {
        guard pace.isFinite, pace > 0, let slowest = paceRange(zone: 1, in: paceModel), let fastest = paceRange(zone: 5, in: paceModel) else { return nil }
        if pace > slowest.upperBound { return (1, false) }
        if pace < fastest.lowerBound { return (6, false) }
        for zone in 1...5 {
            guard let range = paceRange(zone: zone, in: paceModel), range.contains(pace) else { continue }
            let width = range.upperBound - range.lowerBound
            return (Double(zone) + (width > 0 ? (range.upperBound - pace) / width : 0), true)
        }
        return nil
    }

    /// A ``IntensityTarget/phaseIntensity`` step: the target becomes the zone positions of the phase pace ±
    /// ``fractionPaceTolerance``, and the companion that pace range. A phase pace outside every zone (not just its
    /// band) gives the whole edge zone and is reported.
    private static func resolvePhaseIntensity(in step: inout WorkoutStep, phasePace: Double, paceModel: PaceModel) -> UnresolvedReason? {
        let tolerance = phasePace * fractionPaceTolerance
        guard let centre = zonePosition(forPace: phasePace, in: paceModel),
              let slow = zonePosition(forPace: phasePace + tolerance, in: paceModel),
              let fast = zonePosition(forPace: phasePace - tolerance, in: paceModel) else { return .zoneUnavailable(0) }
        step.companionTarget = .pace((phasePace - tolerance)...(phasePace + tolerance))
        guard centre.exact else {
            // Slower than zone 1 or faster than zone 5 for this athlete: the whole nearest zone is the target.
            let zone = centre.position <= 1 ? 1 : 5
            step.target = .heartRateZoneRange(Double(zone)...Double(zone + 1))
            return .paceOutsideZone(zone: zone, paceZone: nil)
        }
        step.target = .heartRateZoneRange(min(slow.position, fast.position)...max(slow.position, fast.position))
        return nil
    }

    private static func resolveZone(
        _ target: IntensityTarget?, in step: inout WorkoutStep, zoneModel: HeartRateZoneModel?, paceModel: PaceModel, phasePace: Double?
    ) -> UnresolvedReason? {
        guard let zoneModel else { return .noHeartRateZones }
        let zone = zoneNumber(of: target)
        guard let positions = zonePositions(of: target), zoneModel.zoneBPMRange(positions: positions) != nil,
              let zonePace = paceRange(zonePositions: positions, in: paceModel) else {
            return .zoneUnavailable(zone)
        }
        step.companionTarget = .pace(zonePace)
        guard let phasePace else { return nil }
        guard zonePace.contains(phasePace) else {
            return .paceOutsideZone(zone: zone, paceZone: Self.zone(forPace: phasePace, in: paceModel))
        }
        let tolerance = phasePace * fractionPaceTolerance
        step.companionTarget = .pace((phasePace - tolerance)...(phasePace + tolerance))
        return nil
    }

    /// Turns the heart-rate zone targets of `workout` into bpm ranges, for sending the workout to a device or
    /// running it (MVP5-148). The plan keeps zone positions; this is where the athlete's zones become heart
    /// rates, with the settings in effect on `date`, so a workout sent after the zones changed follows them and
    /// one already on the watch does not.
    ///
    /// `.heartRateZone(n)` and `.heartRateZoneRange` become `.heartRateRange`; every other target, and the
    /// ``WorkoutStep/companionTarget``, is kept. A step it cannot convert (no zone settings, or a zone with no
    /// bpm range under the zone method) keeps its zone target and is reported.
    ///
    /// - Parameters:
    ///   - workout: The workout to convert; not modified.
    ///   - date: The day the workout is done; picks the zone settings in effect.
    ///   - athlete: Supplies the date-effective heart-rate zones.
    /// - Returns: The workout with bpm targets, and the steps that could not be converted.
    public static func resolveBPM(_ workout: StructuredWorkout, on date: Date, athlete: AthleteProfile) -> StepTargetResolution {
        let zoneModel = athlete.heartRateZoneSettings(asOf: date).map { HeartRateZoneModel(settings: $0) }
        var converted = workout
        var unresolved: [UnresolvedStep] = []
        for (blockIndex, block) in workout.blocks.enumerated() {
            for (stepIndex, step) in block.steps.enumerated() {
                switch step.target {
                case .heartRateZone, .heartRateZoneRange:
                    if let reason = convert(step, at: (blockIndex, stepIndex), zoneModel: zoneModel, into: &converted) {
                        unresolved.append(UnresolvedStep(blockIndex: blockIndex, stepIndex: stepIndex, reason: reason))
                    }
                default:
                    break
                }
            }
        }
        return StepTargetResolution(workout: converted, unresolved: unresolved)
    }

    private static func convert(
        _ step: WorkoutStep, at index: (block: Int, step: Int), zoneModel: HeartRateZoneModel?, into workout: inout StructuredWorkout
    ) -> UnresolvedReason? {
        guard let zoneModel else { return .noHeartRateZones }
        guard let positions = zonePositions(of: step.target), let bpm = zoneModel.zoneBPMRange(positions: positions) else {
            return .zoneUnavailable(zoneNumber(of: step.target))
        }
        // A whole zone is the zone's own range, to the digit, as it was before zone positions.
        let range: ClosedRange<Double>
        if case .heartRateZone(let zone) = step.target, let whole = zoneModel.zoneBPMRange(zone) { range = whole } else { range = bpm }
        workout.blocks[index.block].steps[index.step].target = .heartRateRange(range.lowerBound, range.upperBound)
        return nil
    }
}
