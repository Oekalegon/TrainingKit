import Foundation
import Testing
@testable import TrainingCore

@Suite("RestingHeartRateSmoother")
struct RestingHeartRateSmootherTests {
    let smoother = RestingHeartRateSmoother()

    @Test("no readings smooths to nil")
    func empty() {
        #expect(smoother.smoothedRestingHeartRateBPM(from: []) == nil)
    }

    @Test("a single reading smooths to itself")
    func single() {
        #expect(smoother.smoothedRestingHeartRateBPM(from: [52]) == 52)
    }

    @Test("an odd number of readings smooths to the middle value, ignoring outliers")
    func oddCountIgnoresOutlier() {
        let readings: [Double] = [50, 51, 49, 90, 52]

        let smoothed = smoother.smoothedRestingHeartRateBPM(from: readings)

        #expect(smoothed == 51)
    }

    @Test("an even number of readings smooths to the average of the two middle values")
    func evenCountAveragesMiddlePair() {
        let readings: [Double] = [48, 50, 52, 54]

        let smoothed = smoother.smoothedRestingHeartRateBPM(from: readings)

        #expect(smoothed == 51)
    }

    @Test("reading order doesn't affect the result")
    func orderIndependent() {
        let sorted = smoother.smoothedRestingHeartRateBPM(from: [45, 50, 55, 60, 65])
        let shuffled = smoother.smoothedRestingHeartRateBPM(from: [60, 45, 65, 50, 55])

        #expect(sorted == shuffled)
    }
}
