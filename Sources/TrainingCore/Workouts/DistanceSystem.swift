/// How ``WorkoutTemplate/defaultTitle(values:distanceSystem:)`` writes a distance.
public enum DistanceSystem: Sendable, Hashable {
    /// Meters below 1 km, kilometers above: "400 m", "23 km".
    case metric
    /// Yards below half a mile, miles above: "440 yd", "13.1 mi".
    case imperial
}
