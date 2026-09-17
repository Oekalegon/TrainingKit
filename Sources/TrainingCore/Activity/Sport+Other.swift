/// The `HKWorkoutActivityType` raw-value label format shared by every adapter's `.other` mapping.
///
/// `TrainingCore` never imports HealthKit, but both `TrainingHealthKit` (`Sport(healthKitActivityType:)`)
/// and `TrainingWorkoutKit` (`Sport(workoutKitActivityType:)`/`Sport.workoutKitActivityType`) map an
/// unrecognized `HKWorkoutActivityType` onto `Sport.other`, labeled with its raw value so the
/// original type isn't lost even though `Sport` can't represent it precisely. Without a shared
/// format, the two adapters' labels could silently drift apart, breaking round-tripping a
/// `Sport.other` built by one adapter through the other's reverse mapping. These two helpers are
/// the one place that format is defined.
extension Sport {
    /// The `.other` label for an unrecognized `HKWorkoutActivityType` with this raw value.
    public static func otherLabel(rawValue: UInt) -> String {
        "HKWorkoutActivityType(rawValue: \(rawValue))"
    }

    /// The raw value encoded in this sport's `.other` label, if `self` is `.other` and its label
    /// was produced by ``otherLabel(rawValue:)``. `nil` for every other case, and for an `.other`
    /// label that wasn't built by ``otherLabel(rawValue:)`` (e.g. one typed in by hand).
    public var otherRawValue: UInt? {
        guard case .other(let label) = self else { return nil }
        let prefix = "HKWorkoutActivityType(rawValue: "
        guard label.hasPrefix(prefix), label.hasSuffix(")"),
              let rawValue = UInt(label.dropFirst(prefix.count).dropLast())
        else {
            return nil
        }
        return rawValue
    }
}
