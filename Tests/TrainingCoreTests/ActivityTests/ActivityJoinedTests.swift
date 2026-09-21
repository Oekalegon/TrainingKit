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

    @Test("perceivedExertion is duration-weighted, bounds are unioned, and sport is the longer piece's")
    func exertionBoundsAndSport() {
        let a = Activity(
            source: .manual, sport: .running, start: t0, duration: 100,
            geographicBounds: GeographicBounds(minLatitude: 1, maxLatitude: 2, minLongitude: 3, maxLongitude: 4),
            perceivedExertion: 4
        )
        let b = Activity(
            source: .manual, sport: .outdoorRunning, start: t0.addingTimeInterval(110), duration: 300,
            geographicBounds: GeographicBounds(minLatitude: 0, maxLatitude: 1.5, minLongitude: 3.5, maxLongitude: 9),
            perceivedExertion: 8
        )

        let merged = Activity.joined(a, b)

        #expect(merged.perceivedExertion == 7)  // (4*100 + 8*300) / 400 = 7
        #expect(merged.geographicBounds == GeographicBounds(minLatitude: 0, maxLatitude: 2, minLongitude: 3, maxLongitude: 9))
        #expect(merged.sport == .outdoorRunning)
        #expect(Activity.joined(a, Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(110), duration: 300, perceivedExertion: nil)).perceivedExertion == 4)
    }

    @Test("When both pieces are linked to different plans, the earlier piece's link wins")
    func differentPlansEarlierWins() {
        let planA = UUID()
        let planB = UUID()
        let a = Activity(source: .manual, sport: .running, start: t0, duration: 100, linkedPlanID: planA)
        let b = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(110), duration: 100, linkedPlanID: planB)

        #expect(Activity.joined(b, a).linkedPlanID == planA)
    }

    @Test("Heart-rate TRIMP bridges a sub-60 s gap between pieces but not a longer one")
    func trimpBridgesOnlyShortGaps() throws {
        let athlete = AthleteProfile.fixture()
        let calculator = ExponentialTRIMPCalculator()
        func pieces(gap: TimeInterval) -> (Activity, Activity) {
            let a = Activity(
                source: .manual, sport: .running, start: t0, duration: 600,
                heartRate: [HeartRateSample(time: t0, bpm: 150), HeartRateSample(time: t0.addingTimeInterval(600), bpm: 150)]
            )
            let start = t0.addingTimeInterval(600 + gap)
            let b = Activity(
                source: .manual, sport: .running, start: start, duration: 600,
                heartRate: [HeartRateSample(time: start, bpm: 150), HeartRateSample(time: start.addingTimeInterval(600), bpm: 150)]
            )
            return (a, b)
        }

        for (gap, bridged) in [(17.0, true), (120.0, false)] {
            let (a, b) = pieces(gap: gap)
            let separate = try calculator.load(for: a, athlete: athlete).value + calculator.load(for: b, athlete: athlete).value
            let joined = try calculator.load(for: Activity.joined(a, b), athlete: athlete).value
            if bridged {
                #expect(joined > separate)
            } else {
                #expect(abs(joined - separate) < 1e-9)
            }
        }
    }
}
