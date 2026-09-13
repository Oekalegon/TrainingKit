import Foundation
import Testing
@testable import TrainingCore

@Suite("ActivityOverlapChecker")
struct ActivityOverlapCheckerTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    @Test("Non-overlapping, far-apart activities produce no advice")
    func noAdvice() {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(
            source: .manual, sport: .cycling, start: day(0).addingTimeInterval(3 * 3600), duration: 1800
        )

        #expect(ActivityOverlapChecker.findOverlaps(in: [first, second]).isEmpty)
    }

    @Test("Same time span, same sport, identical data is advised as a duplicate")
    func duplicate() throws {
        let heartRate = [HeartRateSample(time: day(0), bpm: 140)]
        let first = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800, heartRate: heartRate
        )
        let second = Activity(
            source: .fitFile(URL(fileURLWithPath: "/tmp/a.fit")), sport: .running, start: day(0),
            duration: 1800, heartRate: heartRate
        )

        let advice = ActivityOverlapChecker.findOverlaps(in: [first, second])

        #expect(advice.count == 1)
        let found = try #require(advice.first)
        #expect(Set([found.first, found.second]) == Set([first.id, second.id]))
        guard case .duplicate(let keep, let remove) = found.recommendation else {
            Issue.record("expected .duplicate, got \(String(describing: found.recommendation))")
            return
        }
        #expect(Set([keep, remove]) == Set([first.id, second.id]))
    }

    @Test("Activities with matching times/sport but differing data (not a literal duplicate) are advised as a merge, not a duplicate")
    func mismatchedDataIsNotADuplicate() throws {
        let sparse = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let rich = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800,
            heartRate: [HeartRateSample(time: day(0), bpm: 140)]
        )

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [sparse, rich]).first)
        #expect(advice.recommendation == .merge)
    }

    @Test("Same time span and sport with differing data is advised as a merge")
    func merge() throws {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800, distanceMeters: 5000)
        let second = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800, distanceMeters: 5200
        )

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .merge)
    }

    @Test("Overlapping activities with a different sport are advised as a conflict")
    func conflictDifferentSport() throws {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .cycling, start: day(0), duration: 1800)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .conflict)
    }

    @Test("Overlapping activities with very different start/end times are advised as a conflict")
    func conflictDifferentTimes() throws {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 3600)
        let second = Activity(
            source: .manual, sport: .running, start: day(0).addingTimeInterval(1800), duration: 3600
        )

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .conflict)
    }

    @Test("A sub-activity fully contained in another is advised as possible multisport")
    func containedSubActivity() throws {
        let triathlon = Activity(source: .manual, sport: .other("triathlon"), start: day(0), duration: 3 * 3600)
        let swimLeg = Activity(source: .manual, sport: .swimming, start: day(0), duration: 1200)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [triathlon, swimLeg]).first)
        #expect(advice.recommendation == .possibleMultisport)
    }

    @Test("Non-overlapping activities with a short gap are advised as possible multisport")
    func closeGapIsPossibleMultisport() throws {
        let swim = Activity(source: .manual, sport: .swimming, start: day(0), duration: 1200)
        let bike = Activity(
            source: .manual, sport: .cycling, start: day(0).addingTimeInterval(1200 + 10 * 60), duration: 3600
        )

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [swim, bike]).first)
        #expect(advice.recommendation == .possibleMultisport)
    }

    @Test("Non-overlapping activities with a gap beyond the threshold produce no advice")
    func largeGapProducesNoAdvice() {
        let swim = Activity(source: .manual, sport: .swimming, start: day(0), duration: 1200)
        let bike = Activity(
            source: .manual, sport: .cycling, start: day(0).addingTimeInterval(1200 + 45 * 60), duration: 3600
        )

        #expect(ActivityOverlapChecker.findOverlaps(in: [swim, bike]).isEmpty)
    }

    @Test("Activities that touch at exactly one instant (zero gap) are advised as possible multisport")
    func touchingEndpointsIsPossibleMultisport() throws {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .running, start: day(0).addingTimeInterval(1800), duration: 1800)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .possibleMultisport)
    }

    @Test("Custom thresholds change the same-session and multisport-gap boundaries")
    func customThresholds() {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(
            source: .manual, sport: .running, start: day(0).addingTimeInterval(400), duration: 1800
        )
        let tightThresholds = ActivityOverlapThresholds(sameSessionTolerance: 60, multisportGapTolerance: 60)

        // Beyond the tight same-session tolerance, and no containment — falls through to conflict.
        let advice = ActivityOverlapChecker.findOverlaps(in: [first, second], thresholds: tightThresholds)
        #expect(advice.first?.recommendation == .conflict)
    }

    @Test("Empty and single-activity input produce no advice")
    func trivialInputs() {
        #expect(ActivityOverlapChecker.findOverlaps(in: []).isEmpty)
        let only = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        #expect(ActivityOverlapChecker.findOverlaps(in: [only]).isEmpty)
    }
}
