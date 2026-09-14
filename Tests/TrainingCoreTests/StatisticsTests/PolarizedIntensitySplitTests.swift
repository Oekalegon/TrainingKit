import Foundation
import Testing
@testable import TrainingCore

@Suite("PolarizedIntensitySplit")
struct PolarizedIntensitySplitTests {
    @Test("TimeInZone.polarizedSplit groups zone 0-2 as low and zones 3-5 as moderate-to-high")
    func polarizedSplitGroupsZonesCorrectly() {
        let timeInZone = TimeInZone(seconds: [
            0: 60, 1: 120, 2: 180,
            3: 90, 4: 30, 5: 10,
        ])

        let split = timeInZone.polarizedSplit

        #expect(split.lowSeconds == 360)
        #expect(split.moderateToHighSeconds == 130)
        #expect(split.total == 490)
    }

    @Test("fractions divide each bucket by the combined total, not TimeInZone's own total")
    func fractionsUseSplitTotal() {
        let split = PolarizedIntensitySplit(lowSeconds: 800, moderateToHighSeconds: 200)

        #expect(split.lowFraction == 0.8)
        #expect(split.moderateToHighFraction == 0.2)
    }

    @Test("fractions are 0 when total is 0, not NaN")
    func fractionsAreZeroWhenTotalIsZero() {
        let split = PolarizedIntensitySplit(lowSeconds: 0, moderateToHighSeconds: 0)

        #expect(split.lowFraction == 0)
        #expect(split.moderateToHighFraction == 0)
    }

    @Test("an empty TimeInZone produces an empty split")
    func emptyTimeInZoneProducesEmptySplit() {
        let split = TimeInZone().polarizedSplit

        #expect(split.lowSeconds == 0)
        #expect(split.moderateToHighSeconds == 0)
    }

    @Test("+ sums each bucket independently, mirroring TimeInZone's own rollup")
    func plusSumsBucketsIndependently() {
        let a = PolarizedIntensitySplit(lowSeconds: 100, moderateToHighSeconds: 20)
        let b = PolarizedIntensitySplit(lowSeconds: 50, moderateToHighSeconds: 30)

        let combined = a + b

        #expect(combined.lowSeconds == 150)
        #expect(combined.moderateToHighSeconds == 50)
    }

    @Test("summing per-activity TimeInZone then splitting matches summing per-activity splits")
    func rollupCommutesWithSplitting() {
        let activity1 = TimeInZone(seconds: [1: 100, 4: 20])
        let activity2 = TimeInZone(seconds: [2: 50, 5: 10])

        let splitOfSum = (activity1 + activity2).polarizedSplit
        let sumOfSplits = activity1.polarizedSplit + activity2.polarizedSplit

        #expect(splitOfSum == sumOfSplits)
    }
}
