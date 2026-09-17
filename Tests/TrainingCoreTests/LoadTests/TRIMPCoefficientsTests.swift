import Testing
@testable import TrainingCore

@Suite("TRIMPCoefficients")
struct TRIMPCoefficientsTests {
    @Test("male and female sexes select their own coefficients")
    func maleAndFemaleCoefficients() {
        let coefficients = TRIMPCoefficients()
        #expect(coefficients.coefficients(for: .male) == (coefficients.maleA, coefficients.maleB))
        #expect(coefficients.coefficients(for: .female) == (coefficients.femaleA, coefficients.femaleB))
    }

    @Test("unspecified falls back to male coefficients")
    func unspecifiedFallsBackToMale() {
        let coefficients = TRIMPCoefficients()
        let unspecified = coefficients.coefficients(for: .unspecified)
        let male = coefficients.coefficients(for: .male)
        #expect(unspecified == male)
    }
}
