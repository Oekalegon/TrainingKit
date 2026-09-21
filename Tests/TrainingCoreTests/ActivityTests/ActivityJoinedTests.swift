import Foundation
import Testing
@testable import TrainingCore

@Suite("Activity.joined")
struct ActivityJoinedTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Combines span, distance, and sample streams in time order")
    func combines() {
        let planID = UUID()
        let first = Activity(
            source: .healthKit(UUID()), sport: .running, start: t0, duration: 343, distanceMeters: 668,
            heartRate: [HeartRateSample(time: t0, bpm: 120)], linkedPlanID: planID
        )
        let second = Activity(
            source: .healthKit(UUID()), sport: .running, start: t0.addingTimeInterval(360), duration: 2643,
            distanceMeters: 5200, heartRate: [HeartRateSample(time: t0.addingTimeInterval(400), bpm: 150)]
        )

        let merged = Activity.joined(second, first)

        #expect(merged.source == .manual)
        #expect(merged.start == t0)
        #expect(merged.duration == 360 + 2643)
        #expect(merged.distanceMeters == 5868)
        #expect(merged.heartRate.map(\.bpm) == [120, 150])
        #expect(merged.linkedPlanID == planID)
        #expect(merged.id != first.id && merged.id != second.id)
    }

    @Test("Nil summaries stay nil; one-sided ones carry over; both-sided ones combine")
    func summaries() {
        let a = Activity(
            source: .manual, sport: .running, start: t0, duration: 100,
            elevation: ElevationStats(gainMeters: 10, lossMeters: 5, minMeters: 2, maxMeters: 12),
            cadence: CadenceStats(min: 60, max: 80, mean: 70, median: 70)
        )
        let b = Activity(
            source: .manual, sport: .running, start: t0.addingTimeInterval(110), duration: 300,
            elevation: ElevationStats(gainMeters: 20, lossMeters: 1, minMeters: 1, maxMeters: 30),
            cadence: CadenceStats(min: 70, max: 90, mean: 90, median: 90)
        )

        let merged = Activity.joined(a, b)

        #expect(merged.distanceMeters == nil)
        #expect(merged.geographicBounds == nil)
        #expect(merged.perceivedExertion == nil)
        #expect(merged.elevation == ElevationStats(gainMeters: 30, lossMeters: 6, minMeters: 1, maxMeters: 30))
        #expect(merged.cadence?.min == 60 && merged.cadence?.max == 90)
        #expect(merged.cadence?.mean == 85)
    }
}
