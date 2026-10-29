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
    case heartRateRange(Double, Double)
    case pace(ClosedRange<Double>)
    case power(ClosedRange<Double>)
    case rpe(Int)
}
