import Foundation
import Testing
@testable import TrainingCore

@Suite("ActivityOverlapChecker")
struct ActivityOverlapCheckerTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    @Test("Non-overlapping activities produce no findings")
    func noOverlap() {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .cycling, start: day(0).addingTimeInterval(3600), duration: 1800)

        #expect(ActivityOverlapChecker.findOverlaps(in: [first, second]).isEmpty)
    }

    @Test("Overlapping activities produce a finding regardless of sport")
    func overlapAcrossSports() throws {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 3600)
        let second = Activity(source: .manual, sport: .cycling, start: day(0).addingTimeInterval(1800), duration: 3600)

        let overlaps = ActivityOverlapChecker.findOverlaps(in: [first, second])

        #expect(overlaps.count == 1)
        let overlap = try #require(overlaps.first)
        #expect(Set([overlap.first, overlap.second]) == Set([first.id, second.id]))
        #expect(overlap.overlappingRange == day(0).addingTimeInterval(1800)...day(0).addingTimeInterval(3600))
    }

    @Test("A sub-activity fully contained in another is not flagged (triathlon leg case)")
    func containedSubActivityExcluded() {
        let triathlon = Activity(source: .manual, sport: .other("triathlon"), start: day(0), duration: 3 * 3600)
        let swimLeg = Activity(
            source: .manual, sport: .swimming, start: day(0).addingTimeInterval(0), duration: 1200
        )

        #expect(ActivityOverlapChecker.findOverlaps(in: [triathlon, swimLeg]).isEmpty)
    }

    @Test("Activities that merely touch at an endpoint are not flagged")
    func touchingEndpointsNotFlagged() {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .running, start: day(0).addingTimeInterval(1800), duration: 1800)

        #expect(ActivityOverlapChecker.findOverlaps(in: [first, second]).isEmpty)
    }

    @Test("Three mutually overlapping activities produce three pairwise findings")
    func threeWayOverlap() {
        let a = Activity(source: .manual, sport: .running, start: day(0), duration: 3600)
        let b = Activity(source: .manual, sport: .running, start: day(0).addingTimeInterval(600), duration: 3600)
        let c = Activity(source: .manual, sport: .running, start: day(0).addingTimeInterval(1200), duration: 3600)

        #expect(ActivityOverlapChecker.findOverlaps(in: [a, b, c]).count == 3)
    }

    @Test("Empty and single-activity input produce no findings")
    func trivialInputs() {
        #expect(ActivityOverlapChecker.findOverlaps(in: []).isEmpty)
        let only = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        #expect(ActivityOverlapChecker.findOverlaps(in: [only]).isEmpty)
    }
}
