/// The kind of activity performed, used to select load calculators and match completed
/// activities to planned ones.
public enum Sport: Sendable, Codable, Hashable {
    case running
    case cycling
    case swimming
    case strength
    case walking
    case rowing
    case other(String)
}
