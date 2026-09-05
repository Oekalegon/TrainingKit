/// The athlete's biological sex, used to select TRIMP coefficients.
///
/// `.unspecified` uses the male coefficients (``TRIMPCoefficients``), which is the more
/// conservative (lower TRIMP for the same relative intensity) of the two defaults.
public enum BiologicalSex: Sendable, Codable, Hashable {
    case male
    case female
    case unspecified
}
