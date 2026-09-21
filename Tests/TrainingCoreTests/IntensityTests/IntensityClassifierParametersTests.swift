import Foundation
import Testing
@testable import TrainingCore

@Suite("IntensityClassifierParameters")
struct IntensityClassifierParametersTests {
    private let parameters = IntensityClassifierParameters()

    private func category(
        total: TimeInterval, hard: TimeInterval = 0, moderate: TimeInterval = 0, aboveFirstZone: TimeInterval? = nil
    ) -> IntensityCategory {
        parameters.category(
            totalSeconds: total,
            hardSeconds: hard,
            moderateSeconds: moderate,
            aboveFirstZoneSeconds: aboveFirstZone ?? hard + moderate
        )
    }

    @Test("categories are ordered from very low to high")
    func categoriesAreOrdered() {
        #expect(IntensityCategory.veryLow < .low)
        #expect(IntensityCategory.low < .medium)
        #expect(IntensityCategory.medium < .high)
        #expect(IntensityCategory.allCases.sorted() == [.veryLow, .low, .medium, .high])
    }

    @Test("hard time reaches high at exactly the larger of 6 minutes and 10 % of the session")
    func highBoundary() {
        #expect(category(total: 3600, hard: 360) == .high)
        #expect(category(total: 3600, hard: 359) != .high)
        // 10 % of a 2 h session is 12 minutes, which exceeds the 6 minute floor.
        #expect(category(total: 7200, hard: 600) != .high)
        #expect(category(total: 7200, hard: 720) == .high)
    }

    @Test("a single 3 minute hard effort in a 60 minute run stays low")
    func shortHardEffortDoesNotChangeCategory() {
        #expect(category(total: 3600, hard: 180, aboveFirstZone: 3600) == .low)
    }

    @Test("tempo time reaches medium at exactly the larger of 8 minutes and 15 % of the session")
    func mediumBoundary() {
        #expect(category(total: 3000, moderate: 480) == .medium)
        #expect(category(total: 3000, moderate: 479, aboveFirstZone: 3000) == .low)
        // 15 % of a 2 h run is 18 minutes.
        #expect(category(total: 7200, moderate: 720, aboveFirstZone: 7200) == .low)
        #expect(category(total: 7200, moderate: 1080) == .medium)
    }

    @Test("hard and moderate time add up towards medium")
    func hardAndModerateCombineForMedium() {
        // 5 + 5 minutes clears 15 % of a 60 minute session (9 minutes), although 5 minutes of hard
        // time alone is short of the 6 minute floor for high.
        #expect(category(total: 3600, hard: 300, moderate: 300) == .medium)
        #expect(category(total: 3600, hard: 240, moderate: 240, aboveFirstZone: 3600) == .low)
    }

    @Test("a session with almost nothing above zone 1 is very low")
    func veryLowBoundary() {
        #expect(category(total: 3600, aboveFirstZone: 359) == .veryLow)
        #expect(category(total: 3600, aboveFirstZone: 360) == .low)
    }
}
