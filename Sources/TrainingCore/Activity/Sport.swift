/// The kind of activity performed, used to select load calculators and match completed
/// activities to planned ones.
public enum Sport: Sendable, Codable, Hashable {
    case running
    /// A run explicitly recorded as indoors (e.g. a treadmill), as distinct from ``running``'s
    /// ambiguous/unspecified venue. See ``isSameFamily(as:)``.
    case indoorRunning
    /// A run explicitly recorded as outdoors, as distinct from ``running``'s ambiguous/unspecified
    /// venue. See ``isSameFamily(as:)``.
    case outdoorRunning
    case cycling
    case swimming
    case strength
    case walking
    case rowing
    case hiking
    case other(String)

    /// Whether `self` and `other` should be treated as the same kind of activity for
    /// ``ActivityOverlapChecker``'s same-sport checks, even when they aren't the exact same case —
    /// e.g. a hike and a walk, or a plain run and an indoor (treadmill) run.
    ///
    /// The one deliberate exception: an activity explicitly tagged ``outdoorRunning`` and one
    /// explicitly tagged ``indoorRunning`` are NOT considered the same family, since both sides
    /// having gone out of their way to record a venue means the distinction is meaningful — unlike
    /// plain ``running``, whose venue is unspecified and so compatible with either.
    public func isSameFamily(as other: Sport) -> Bool {
        if self == other { return true }

        let hikingOrWalking: Set<Sport> = [.hiking, .walking]
        if hikingOrWalking.contains(self), hikingOrWalking.contains(other) { return true }

        let runningFamily: Set<Sport> = [.running, .indoorRunning, .outdoorRunning]
        guard runningFamily.contains(self), runningFamily.contains(other) else { return false }
        return Set([self, other]) != [.indoorRunning, .outdoorRunning]
    }
}
