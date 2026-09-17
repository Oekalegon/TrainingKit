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
}
