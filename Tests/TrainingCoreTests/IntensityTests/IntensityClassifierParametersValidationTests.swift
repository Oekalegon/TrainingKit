import Foundation
import Testing
@testable import TrainingCore

@Suite("IntensityClassifierParameters validation")
struct IntensityClassifierParametersValidationTests {
    @Test("a non-finite value falls back to its default instead of disabling a category")
    func nonFiniteFallsBack() {
        let parameters = IntensityClassifierParameters(
            highMinimumSeconds: .nan, highMinimumFraction: .infinity, mediumMinimumSeconds: -.infinity,
            mediumMinimumFraction: .nan, lowMinimumFraction: .nan, minimumExcursionSeconds: .nan, heartRateLagSeconds: .infinity
        )

        #expect(parameters == IntensityClassifierParameters())
        // A NaN threshold would make every comparison false, so `high` could never fire.
        #expect(parameters.category(totalSeconds: 3600, hardSeconds: 1800, moderateSeconds: 0, aboveFirstZoneSeconds: 1800) == .high)
    }

    @Test("times are clamped to non-negative and fractions to 0...1")
    func outOfRangeIsClamped() {
        let parameters = IntensityClassifierParameters(
            highMinimumSeconds: -5, highMinimumFraction: 4, mediumMinimumSeconds: -1,
            mediumMinimumFraction: -0.5, lowMinimumFraction: 2, minimumExcursionSeconds: -60, heartRateLagSeconds: -30
        )

        #expect(parameters.highMinimumSeconds == 0)
        #expect(parameters.highMinimumFraction == 1)
        #expect(parameters.mediumMinimumSeconds == 0)
        #expect(parameters.mediumMinimumFraction == 0)
        #expect(parameters.lowMinimumFraction == 1)
        #expect(parameters.minimumExcursionSeconds == 0)
        #expect(parameters.heartRateLagSeconds == 0)
    }

    @Test("valid values are kept as given")
    func validValuesAreKept() {
        let parameters = IntensityClassifierParameters(highMinimumSeconds: 300, highMinimumFraction: 0.2, heartRateLagSeconds: 0)

        #expect(parameters.highMinimumSeconds == 300)
        #expect(parameters.highMinimumFraction == 0.2)
        #expect(parameters.heartRateLagSeconds == 0)
    }
}
