/// The `(a, b)` coefficients in Banister's exponential TRIMP weighting function
/// `weight = a * exp(b * ratio)`, split by biological sex per Banister's original derivation.
///
/// Held as a value (rather than hardcoded) so MVP 3 calibration can tune them per athlete.
public struct TRIMPCoefficients: Sendable, Codable, Hashable {
    /// The `a` coefficient used for male (and `.unspecified`) athletes.
    public var maleA: Double
    /// The `b` coefficient used for male (and `.unspecified`) athletes.
    public var maleB: Double
    /// The `a` coefficient used for female athletes.
    public var femaleA: Double
    /// The `b` coefficient used for female athletes.
    public var femaleB: Double

    /// Creates a coefficient set, defaulting to Banister's original values.
    ///
    /// - Parameters:
    ///   - maleA: The `a` coefficient for male/`.unspecified` athletes.
    ///   - maleB: The `b` coefficient for male/`.unspecified` athletes.
    ///   - femaleA: The `a` coefficient for female athletes.
    ///   - femaleB: The `b` coefficient for female athletes.
    public init(maleA: Double = 0.64, maleB: Double = 1.92, femaleA: Double = 0.86, femaleB: Double = 1.67) {
        self.maleA = maleA
        self.maleB = maleB
        self.femaleA = femaleA
        self.femaleB = femaleB
    }

    /// The `(a, b)` pair to use for the given sex. `.unspecified` uses the male coefficients.
    public func coefficients(for sex: BiologicalSex) -> (a: Double, b: Double) {
        switch sex {
        case .male, .unspecified:
            return (maleA, maleB)
        case .female:
            return (femaleA, femaleB)
        }
    }
}
