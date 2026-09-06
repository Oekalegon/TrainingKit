import TrainingCore
import Foundation

#if canImport(WorkoutKit)
import WorkoutKit

extension IntensityTarget {
    /// Maps this target onto a WorkoutKit alert, or `nil` if none applies.
    ///
    /// - `.pace` is stored in seconds per kilometer, matching `PaceModel`'s convention; it's
    ///   converted to a `SpeedRangeAlert` (WorkoutKit has no pace-based alert), inverting the
    ///   range since a faster (smaller) pace is a higher speed.
    /// - `.rpe` has no WorkoutKit equivalent — there's no alert type based on perceived exertion —
    ///   so it always maps to `nil`, the same "not representable on the watch" gap
    ///   `TrainingHealthKit`'s import notes for `Activity.perceivedExertion` in the other direction.
    public var workoutAlert: (any WorkoutAlert)? {
        switch self {
        case .heartRateZone(let zone):
            return HeartRateZoneAlert(zone: zone)
        case .heartRateRange(let low, let high):
            // Unlike `.pace`/`.power` (already `ClosedRange<Double>` in Core, so already
            // guaranteed ordered), `.heartRateRange` is two loose `Double`s with no ordering
            // guarantee — building `ClosedRange` from them directly would trap if a caller ever
            // passes them reversed. `min`/`max` makes this total, matching the `.pace` case below.
            let unit = WorkoutAlertMetric.countPerMinute
            let lowM = Measurement(value: min(low, high), unit: unit)
            let highM = Measurement(value: max(low, high), unit: unit)
            return HeartRateRangeAlert(target: lowM...highM)
        case .pace(let range):
            // A non-positive pace (0 or negative seconds/km) has no corresponding speed —
            // 1000/range.lowerBound would silently produce .infinity/a negative value rather than
            // a crash, which is harmless today only because HeartRateZoneModel.intensityRatio(for:)
            // ignores the actual .pace/.power bounds and returns a fixed zone-4 approximation. Once
            // a real pace/power zone model reads these values, a silently infinite bound would
            // become a genuine correctness bug instead of a no-op, so this returns nil now rather
            // than waiting for that to surface as one.
            guard range.lowerBound > 0 else { return nil }
            let fastSpeed = 1000 / range.lowerBound
            let slowSpeed = 1000 / range.upperBound
            let low = min(fastSpeed, slowSpeed)
            let high = max(fastSpeed, slowSpeed)
            return SpeedRangeAlert(
                target: Measurement(value: low, unit: .metersPerSecond)...Measurement(value: high, unit: .metersPerSecond),
                metric: .average
            )
        case .power(let range):
            return PowerRangeAlert(target: Measurement(value: range.lowerBound, unit: .watts)...Measurement(value: range.upperBound, unit: .watts))
        case .rpe:
            return nil
        }
    }

    /// Maps a WorkoutKit alert onto its `IntensityTarget` equivalent, or `nil` if this alert has
    /// no equivalent.
    ///
    /// `PowerZoneAlert` and every threshold/cadence alert (`PowerThresholdAlert`,
    /// `SpeedThresholdAlert`, `CadenceThresholdAlert`, `CadenceRangeAlert`) fall through to `nil`
    /// — `IntensityTarget` has no power-zone or cadence case, and no single-value-threshold shape
    /// for any metric, only ranges and heart-rate zones.
    ///
    /// - Parameter alert: The WorkoutKit alert to map.
    public init?(workoutAlert alert: any WorkoutAlert) {
        switch alert {
        case let zoneAlert as HeartRateZoneAlert:
            self = .heartRateZone(zoneAlert.zone)
        case let rangeAlert as HeartRateRangeAlert:
            let unit = WorkoutAlertMetric.countPerMinute
            let low = rangeAlert.target.lowerBound.converted(to: unit).value
            let high = rangeAlert.target.upperBound.converted(to: unit).value
            self = .heartRateRange(low, high)
        case let speedAlert as SpeedRangeAlert:
            let lowSpeed = speedAlert.target.lowerBound.converted(to: .metersPerSecond).value
            let highSpeed = speedAlert.target.upperBound.converted(to: .metersPerSecond).value
            // A non-positive speed has no corresponding pace; see the matching guard in
            // workoutAlert above for why this returns nil rather than an infinite pace value.
            guard lowSpeed > 0 else { return nil }
            let slowPace = 1000 / lowSpeed
            let fastPace = 1000 / highSpeed
            self = .pace(min(fastPace, slowPace)...max(fastPace, slowPace))
        case let powerAlert as PowerRangeAlert:
            let low = powerAlert.target.lowerBound.converted(to: .watts).value
            let high = powerAlert.target.upperBound.converted(to: .watts).value
            self = .power(low...high)
        default:
            return nil
        }
    }
}
#endif
