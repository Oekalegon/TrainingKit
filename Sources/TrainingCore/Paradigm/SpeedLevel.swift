/// How fast the fastest work of a session is, independent of how much time it spends in the hard
/// heart-rate zones.
///
/// ``IntensityCategory`` is derived from time in zones, so a session of 8-second hill sprints with
/// long recoveries is `low` there although every sprint is a maximal effort. The speed level
/// records that effort separately: it is the highest zone of the session's work steps (see
/// ``PlannedIntensityClassifier/speedLevel(of:athlete:)``), whatever their duration.
public enum SpeedLevel: String, Sendable, Codable, Hashable, CaseIterable, Comparable {
    /// Work in zone 1–2, or a session with no work steps.
    case slow
    /// The fastest work is in zone 3 (tempo effort).
    case moderate
    /// The fastest work is in zone 4 (threshold effort).
    case fast
    /// The fastest work is in zone 5, or an RPE of 8 or more (a maximal or near-maximal effort), however short.
    case max

    public static func < (lhs: SpeedLevel, rhs: SpeedLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// The level of a work step in heart-rate zone `zone` (1...5).
    ///
    /// - Parameter zone: The zone; values outside 1...5 are clamped.
    public init(zone: Int) {
        switch zone {
        case ...2: self = .slow
        case 3: self = .moderate
        case 4: self = .fast
        default: self = .max
        }
    }
}
