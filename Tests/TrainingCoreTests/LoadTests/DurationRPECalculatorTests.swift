import Foundation
import Testing
@testable import TrainingCore

@Suite("DurationRPECalculator")
struct DurationRPECalculatorTests {
    let athlete = AthleteProfile(
        restingHeartRateBPM: 50,
        maxHeartRateBPM: 190,
        sex: .male,
        paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
        timeZone: TimeZone(identifier: "UTC")!
    )
    let calculator = DurationRPECalculator()

    @Test("load is duration in minutes times RPE")
    func computesSessionRPE() throws {
        let activity = Activity(
            source: .manual, sport: .strength, start: Date(), duration: 3600, perceivedExertion: 7
        )
        let load = try calculator.load(for: activity, athlete: athlete)
        #expect(load.value == 60 * 7)
        #expect(load.method == .durationRPE)
    }

    @Test("missing RPE throws")
    func missingRPEThrows() {
        let activity = Activity(source: .manual, sport: .strength, start: Date(), duration: 3600)
        #expect(throws: LoadError.missingPerceivedExertion) {
            try calculator.load(for: activity, athlete: athlete)
        }
    }
}
