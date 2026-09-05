import Foundation
import Testing
@testable import TrainingCore

@Suite("TanakaHRMaxEstimator")
struct TanakaHRMaxEstimatorTests {
    let estimator = TanakaHRMaxEstimator()

    @Test("a 30-year-old estimates to the textbook Tanaka value")
    func thirtyYearOld() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let dateOfBirth = today.addingTimeInterval(-30 * 365.2425 * 86400)

        let hrMax = estimator.estimatedMaxHeartRateBPM(dateOfBirth: dateOfBirth, asOf: today)

        #expect(abs(hrMax - (208 - 0.7 * 30)) < 1e-6)
    }

    @Test("a newborn (age 0) estimates to 208")
    func ageZero() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)

        let hrMax = estimator.estimatedMaxHeartRateBPM(dateOfBirth: today, asOf: today)

        #expect(abs(hrMax - 208) < 1e-6)
    }
}
