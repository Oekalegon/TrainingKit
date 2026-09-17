/// The intensity a ``WorkoutStep`` targets.
///
/// This shape is deliberately a superset-neutral match for Apple WorkoutKit's `WorkoutGoal`/
/// `WorkoutAlert` and for FIT workout steps, so adapters can map 1:1 without extra fields.
public enum IntensityTarget: Sendable, Codable, Hashable {
    case heartRateZone(Int)
    case heartRateRange(Double, Double)
    case pace(ClosedRange<Double>)
    case power(ClosedRange<Double>)
    case rpe(Int)
}
