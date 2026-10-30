/// The intensity a ``WorkoutStep`` targets.
///
/// This shape is deliberately a superset-neutral match for Apple WorkoutKit's `WorkoutGoal`/
/// `WorkoutAlert` and for FIT workout steps, so adapters can map 1:1 without extra fields.
public enum IntensityTarget: Sendable, Codable, Hashable {
    /// A whole heart-rate zone, 1 to 5.
    case heartRateZone(Int)
    /// A stretch of the athlete's heart-rate zones as zone positions (MVP5-148): `n.0` is the bottom of zone
    /// `n` and `(n+1).0` its top, so `3.0...3.4` is the lower 40 % of zone 3, `3.0...4.0` all of zone 3 (the
    /// same as `.heartRateZone(3)`) and `6.0` the top of zone 5. Positions run from 1.0 to 6.0. The athlete's
    /// zone settings turn it into bpm only when the workout is sent or run, see
    /// ``StepTargetResolver/resolveBPM(_:on:athlete:)``.
    ///
    /// A workout or template that uses it cannot be decoded by a version without this case (the decoding of the
    /// whole workout fails, so nothing is half-read and written back without the target): update every device
    /// that syncs the library together. Generated plans keep using ``heartRateZone(_:)``.
    case heartRateZoneRange(ClosedRange<Double>)
    /// The intensity of the plan's phase (MVP5-153): a template step that fixes no zone, because the zone depends on the
    /// race. In a plan, ``StepTargetResolver`` turns it into the pace of the race pace divided by the phase's
    /// race-target fraction and into the zone positions that pace sits at in the athlete's pace model, so 86 % of a
    /// marathon pace is an easy zone and 86 % of a 5k pace a threshold one. Outside a plan, or without a fraction, it
    /// stays as it is and reads as a moderate effort (zone 3), with no WorkoutKit alert.
    ///
    /// A workout or template that uses it cannot be decoded by a version without this case, as for
    /// ``heartRateZoneRange(_:)``; the stores skip and log what they cannot decode.
    case phaseIntensity
    case heartRateRange(Double, Double)
    case pace(ClosedRange<Double>)
    case power(ClosedRange<Double>)
    case rpe(Int)
}
