/// How hard a session is, on a four-step scale shared by planned and performed activities.
///
/// The categories are deliberately coarser than heart-rate zones: they describe the *session*,
/// not a moment within it. A long run that never leaves zone 2 is ``low``, a continuous tempo run
/// in zone 3 is ``medium``, and a threshold or interval session in zones 4–5 is ``high`` — even
/// though an interval session spends much of its time in lower zones. See
/// ``IntensityClassifierParameters`` for the rules that separate them.
public enum IntensityCategory: Int, Sendable, Codable, Hashable, CaseIterable, Comparable {
    /// Recovery: essentially all time in zone 1.
    case veryLow = 0
    /// Easy and long runs: aerobic effort with little or no time at tempo or above.
    case low = 1
    /// Tempo runs, fartlek, fast finishes: a meaningful share of time in zone 3.
    case medium = 2
    /// Threshold and interval sessions: a meaningful share of time in zones 4–5.
    case high = 3

    public static func < (lhs: IntensityCategory, rhs: IntensityCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
