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

    @Test("windowStart(endingAt:) is exactly windowInDays before the given date")
    func windowStartIsWindowInDaysEarlier() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)

        let windowStart = smoother.windowStart(endingAt: today)

        #expect(today.timeIntervalSince(windowStart) == Double(RestingHeartRateSmoother.windowInDays) * 86400)
    }

    @Test("dated readings on the same day are averaged into one value before the median, so a noisy multi-sample day doesn't outweigh a single-sample day")
    func sameDayReadingsAreAveragedBeforeMedian() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6))!
        let day1Later = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 20))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 6))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 6))!

        // Day 1 has two samples averaging to 60; without per-day averaging, its two individual
        // values (50, 70) would each count separately and shift the 3-value median away from 55.
        let readings: [(date: Date, bpm: Double)] = [
            (day1, 50), (day1Later, 70), (day2, 50), (day3, 60),
        ]

        let smoothed = smoother.smoothedRestingHeartRateBPM(from: readings, calendar: calendar)

        // Per-day averages: day1 = 60, day2 = 50, day3 = 60 -> median of [60, 50, 60] = 60.
        #expect(smoothed == 60)
    }

    @Test("dated readings with no duplicate days smooth the same as the flat median")
    func datedReadingsWithoutDuplicatesMatchFlatMedian() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 6))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 6))!

        let readings: [(date: Date, bpm: Double)] = [(day1, 48), (day2, 52), (day3, 50)]

        let smoothed = smoother.smoothedRestingHeartRateBPM(from: readings, calendar: calendar)

        #expect(smoothed == 50)
    }

    @Test("no dated readings smooths to nil")
    func emptyDatedReadings() {
        let readings: [(date: Date, bpm: Double)] = []

        #expect(smoother.smoothedRestingHeartRateBPM(from: readings) == nil)
    }

    // MARK: Derived from heart rate samples

    private func day(_ offset: Int, _ bpms: [Double]) -> [(date: Date, bpm: Double)] {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let base = Calendar.current.date(byAdding: .day, value: offset, to: start)!
        return bpms.enumerated().map { (base.addingTimeInterval(Double($0.offset) * 60), $0.element) }
    }

    @Test("a day's resting value is its low percentile, not its minimum")
    func lowPercentileIgnoresArtefact() {
        // Five days of 50...149, one of them with an artefact at 30: the 5th percentile stays near 54.
        let normal = (1..<5).flatMap { day($0, (50..<150).map(Double.init)) }
        let artefact = day(0, [30] + (50..<150).map(Double.init))

        let resting = smoother.restingHeartRateBPM(fromHeartRateSamples: normal + artefact)

        #expect(resting != nil)
        #expect(resting! > 50 && resting! < 56)
    }

    @Test("days with too few samples are ignored")
    func sparseDaysIgnored() {
        let full = day(0, Array(repeating: 52, count: 30))
        let sparse = day(1, [40, 41, 42])

        #expect(smoother.restingHeartRateBPM(fromHeartRateSamples: full + sparse) == 52)
    }

    @Test("the daily values are combined by median")
    func medianAcrossDays() {
        let days = [50.0, 52, 90].enumerated().flatMap { day($0.offset, Array(repeating: $0.element, count: 25)) }

        #expect(smoother.restingHeartRateBPM(fromHeartRateSamples: days) == 52)
    }

    @Test("no qualifying days gives nil")
    func noQualifyingDays() {
        #expect(smoother.restingHeartRateBPM(fromHeartRateSamples: []) == nil)
        #expect(smoother.restingHeartRateBPM(fromHeartRateSamples: day(0, [50, 51])) == nil)
    }

    @Test("the result is capped at 10 bpm above the sleeping minimum")
    func cappedAboveSleepingMinimum() {
        // Each day has one sample at 40 and nineteen at 80, so the 5th percentile is about 78, far above
        // the sleeping minimum of 40, and the cap decides.
        let days = (0..<3).flatMap { day($0, [40] + Array(repeating: 80, count: 19)) }

        let resting = smoother.restingHeartRateBPM(fromHeartRateSamples: days)

        #expect(resting == 40 + RestingHeartRateSmoother.maximumAboveSleepingMinimumBPM)
    }

    @Test("a value within 10 bpm of the sleeping minimum is left alone")
    func notCappedWhenClose() {
        let days = (0..<3).flatMap { day($0, Array(repeating: 52, count: 10) + Array(repeating: 70, count: 10)) }

        #expect(smoother.restingHeartRateBPM(fromHeartRateSamples: days) == 52)
    }

    @Test("a single artefact low doesn't drag the cap down")
    func artefactDoesNotMoveCap() {
        let normal = (1..<5).flatMap { day($0, Array(repeating: 52, count: 25)) }
        let artefact = day(0, [25] + Array(repeating: 52, count: 24))

        #expect(smoother.restingHeartRateBPM(fromHeartRateSamples: normal + artefact) == 52)
    }
}
