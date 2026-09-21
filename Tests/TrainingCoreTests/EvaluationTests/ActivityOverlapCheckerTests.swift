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

    @Test("A duplicate pair prefers keeping whichever copy already has a linkedPlanID")
    func duplicateKeepsLinkedPlanCopy() throws {
        let linked = Activity(
            source: .manual, sport: .running, start: day(0), duration: 1800, linkedPlanID: UUID()
        )
        let unlinked = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [linked, unlinked]).first)
        guard case .duplicate(let keep, let remove) = advice.recommendation else {
            Issue.record("expected .duplicate, got \(String(describing: advice.recommendation))")
            return
        }
        #expect(keep == linked.id)
        #expect(remove == unlinked.id)
    }

    @Test("A hike and a walk with matching data are advised as a duplicate, not a conflict")
    func hikeAndWalkAreSameFamily() throws {
        let first = Activity(source: .manual, sport: .hiking, start: day(0), duration: 1800, distanceMeters: 3000)
        let second = Activity(source: .healthKit(UUID()), sport: .walking, start: day(0), duration: 1800, distanceMeters: 3000)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        guard case .duplicate = advice.recommendation else {
            Issue.record("expected .duplicate, got \(String(describing: advice.recommendation))")
            return
        }
    }

    @Test("A plain run and an indoor run with matching data are advised as a duplicate")
    func plainRunAndIndoorRunAreSameFamily() throws {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .healthKit(UUID()), sport: .indoorRunning, start: day(0), duration: 1800)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        guard case .duplicate = advice.recommendation else {
            Issue.record("expected .duplicate, got \(String(describing: advice.recommendation))")
            return
        }
    }

    @Test("An explicit outdoor run and an explicit indoor run are advised as a conflict, not merged")
    func explicitOutdoorAndIndoorRunConflict() throws {
        let first = Activity(source: .manual, sport: .outdoorRunning, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .indoorRunning, start: day(0), duration: 1800)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .conflict)
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
        let first = Activity(source: .manual, sport: .swimming, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .cycling, start: day(0).addingTimeInterval(1800), duration: 1800)

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

    @Test("Input order doesn't affect which pairs are found, regardless of internal sorting")
    func inputOrderDoesNotMatter() {
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .cycling, start: day(0), duration: 1800)
        let third = Activity(
            source: .manual, sport: .swimming, start: day(0).addingTimeInterval(20 * 3600), duration: 1200
        )

        let inOrder = ActivityOverlapChecker.findOverlaps(in: [first, second, third])
        let reversed = ActivityOverlapChecker.findOverlaps(in: [third, second, first])

        // `first`/`second` are an unordered pair (which activity sorts first when start times tie
        // isn't guaranteed), so compare the pairing itself rather than the raw advice values.
        func unorderedPairs(_ advice: [ActivityOverlapAdvice]) -> Set<Set<UUID>> {
            Set(advice.map { Set([$0.first, $0.second]) })
        }
        #expect(unorderedPairs(inOrder) == unorderedPairs(reversed))
        #expect(inOrder.count == 1)
    }

    @Test("A long-duration activity still finds a pair far later that a short one would have skipped past")
    func longDurationActivityStillFindsDistantPair() throws {
        // The internal scan breaks early per-activity once it's scanned past
        // `multisportGapTolerance` beyond that activity's own end — this confirms a single very
        // long activity (spanning several short ones) still reaches a pair many hours after its
        // start, rather than the early-break accidentally cutting off a genuine containment match.
        let longActivity = Activity(source: .manual, sport: .other("triathlon"), start: day(0), duration: 6 * 3600)
        let shortActivity = Activity(source: .manual, sport: .swimming, start: day(0).addingTimeInterval(5 * 3600), duration: 1200)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [longActivity, shortActivity]).first)
        #expect(advice.recommendation == .possibleMultisport)
    }
}

@Suite("ActivityOverlapChecker join")
struct ActivityOverlapCheckerJoinTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Back-to-back same-sport activities with a sub-minute gap are advised as a join")
    func splitRun() throws {
        // 5:43 run, then a 44:03 run starting ~17s after the first ended.
        let first = Activity(source: .manual, sport: .running, start: t0, duration: 343)
        let second = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(360), duration: 2643)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [second, first]).first)
        #expect(advice.recommendation == .join)
    }

    @Test("A gap of exactly joinGapTolerance is a join; one second more is not")
    func gapBoundary() throws {
        let first = Activity(source: .manual, sport: .running, start: t0, duration: 600)
        func advice(gap: TimeInterval) throws -> OverlapRecommendation {
            let second = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(600 + gap), duration: 600)
            return try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first).recommendation
        }

        #expect(try advice(gap: 300) == .join)
        #expect(try advice(gap: 301) == .possibleMultisport)
    }

    @Test("A custom joinGapTolerance moves the boundary")
    func customJoinTolerance() throws {
        let first = Activity(source: .manual, sport: .running, start: t0, duration: 600)
        let second = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(600 + 120), duration: 600)
        let tight = ActivityOverlapThresholds(joinGapTolerance: 60)

        #expect(try #require(ActivityOverlapChecker.findOverlaps(in: [first, second], thresholds: tight).first).recommendation == .possibleMultisport)
        #expect(try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first).recommendation == .join)
    }

    @Test("A small overlap between same-sport pieces (watch restarted early) is a join, not a conflict")
    func smallOverlap() throws {
        let first = Activity(source: .manual, sport: .running, start: t0, duration: 1800)
        // Starts 20 s before the first ends, runs 40 min: start/end differ by far more than the
        // same-session tolerance, and neither contains the other.
        let second = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(1780), duration: 2400)

        #expect(try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first).recommendation == .join)
    }

    @Test("A larger overlap, a contained activity, or a different sport is not a join")
    func overlapsThatAreNotJoins() throws {
        let long = Activity(source: .manual, sport: .running, start: t0, duration: 3600)
        let bigOverlap = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(1800), duration: 3600)
        let contained = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(600), duration: 300)
        let otherSport = Activity(source: .manual, sport: .cycling, start: t0.addingTimeInterval(3500), duration: 3600)

        #expect(try #require(ActivityOverlapChecker.findOverlaps(in: [long, bigOverlap]).first).recommendation == .conflict)
        #expect(try #require(ActivityOverlapChecker.findOverlaps(in: [long, contained]).first).recommendation == .possibleMultisport)
        #expect(try #require(ActivityOverlapChecker.findOverlaps(in: [long, otherSport]).first).recommendation == .conflict)
    }

    @Test("Thresholds encoded before joinGapTolerance existed still decode, with the default")
    func legacyThresholdsDecode() throws {
        let legacy = Data(#"{"sameSessionTolerance":300,"multisportGapTolerance":1800}"#.utf8)

        let decoded = try JSONDecoder().decode(ActivityOverlapThresholds.self, from: legacy)

        #expect(decoded == ActivityOverlapThresholds())
        let roundTrip = try JSONDecoder().decode(
            ActivityOverlapThresholds.self,
            from: JSONEncoder().encode(ActivityOverlapThresholds(joinGapTolerance: 42))
        )
        #expect(roundTrip.joinGapTolerance == 42)
    }

    @Test("A gap beyond joinGapTolerance stays possibleMultisport")
    func widerGap() throws {
        let first = Activity(source: .manual, sport: .running, start: t0, duration: 600)
        let second = Activity(source: .manual, sport: .running, start: t0.addingTimeInterval(600 + 10 * 60), duration: 600)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .possibleMultisport)
    }

    @Test("A different sport family with a tiny gap stays possibleMultisport")
    func differentSport() throws {
        let first = Activity(source: .manual, sport: .running, start: t0, duration: 600)
        let second = Activity(source: .manual, sport: .cycling, start: t0.addingTimeInterval(630), duration: 600)

        let advice = try #require(ActivityOverlapChecker.findOverlaps(in: [first, second]).first)
        #expect(advice.recommendation == .possibleMultisport)
    }
}
