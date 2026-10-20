import Foundation
import Testing
@testable import TrainingCore

@Suite("VolumeCurveBuilder")
struct VolumeCurveBuilderTests {
    private let builder = VolumeCurveBuilder()

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// Consecutive micros of `length` days with the given roles.
    private func micros(_ roles: [MicroLoadRole], length: Int = 7) -> [Microcycle] {
        roles.enumerated().map { index, role in
            Microcycle(dateRange: day(index * length)...day(index * length + length - 1), phase: .build, loadRole: role, mesoBlockIndex: 0)
        }
    }

    private func volume(_ amount: Double, _ measure: VolumeMeasure = .trimp) -> VolumeTarget {
        VolumeTarget(measure: measure, amount: amount)!
    }

    private func amounts(_ targets: [MicroVolumeTarget]) -> [Double] {
        targets.map { ($0.target.amount * 100).rounded() / 100 }
    }

    @Test("build micros climb linearly from the start to the peak, which lands in the last build micro")
    func linearRamp() throws {
        let result = try builder.targets(for: micros([.build, .build, .build, .build, .build]), starting: volume(100), peak: volume(200))
        #expect(amounts(result) == [100, 125, 150, 175, 200])
    }

    @Test("a single build micro gets the peak; no micros gives an empty curve")
    func edges() throws {
        #expect(amounts(try builder.targets(for: micros([.build]), starting: volume(100), peak: volume(200))) == [200])
        #expect(try builder.targets(for: [], starting: volume(100), peak: volume(200)).isEmpty)
        #expect(amounts(try builder.targets(for: micros([.build, .build]), starting: volume(100), peak: volume(100))) == [100, 100])
    }

    @Test("a recovery micro holds the recovery fraction of the preceding build micro")
    func recovery() throws {
        let result = try builder.targets(for: micros([.build, .build, .recovery, .build]), starting: volume(100), peak: volume(160))
        // Build weekly: 100, 130, 160; recovery: 0.6 x 130.
        #expect(amounts(result) == [100, 130, 78, 160])
    }

    @Test("a recovery before any build uses the first build micro; with no build at all, the start")
    func recoveryWithoutPrecedingBuild() throws {
        #expect(amounts(try builder.targets(for: micros([.recovery, .build]), starting: volume(100), peak: volume(200))) == [120, 200])
        #expect(amounts(try builder.targets(for: micros([.recovery]), starting: volume(100), peak: volume(200))) == [60])
    }

    @Test("taper micros step down linearly from 0.7 to 0.5 of the peak; one taper micro gets 0.6; the race micro 0.3")
    func taperAndRace() throws {
        let two = try builder.targets(for: micros([.build, .build, .taper, .taper, .race]), starting: volume(100), peak: volume(200))
        #expect(amounts(two) == [100, 200, 140, 100, 60])
        let three = try builder.targets(for: micros([.build, .taper, .taper, .taper, .race]), starting: volume(100), peak: volume(200))
        #expect(amounts(three) == [200, 140, 120, 100, 60])
        let one = try builder.targets(for: micros([.build, .taper, .race]), starting: volume(100), peak: volume(200))
        #expect(amounts(one) == [200, 120, 60])
    }

    @Test("targets scale with micro length: 7, 10 and 14 days hold the same weekly volume")
    func lengthScaling() throws {
        for length in [7, 10, 14] {
            let result = try builder.targets(for: micros([.build, .build], length: length), starting: volume(100), peak: volume(200))
            #expect(result.map(\.lengthDays) == [length, length])
            let weekly = result.map { $0.target.amount / Double(length) * 7 }
            #expect(weekly.map { ($0 * 100).rounded() / 100 } == [100, 200])
        }
        // Micros of different lengths in one plan.
        let mixed = [
            Microcycle(dateRange: day(0)...day(6), phase: .build, loadRole: .build, mesoBlockIndex: 0),
            Microcycle(dateRange: day(7)...day(20), phase: .build, loadRole: .build, mesoBlockIndex: 0),
        ]
        #expect(amounts(try builder.targets(for: mixed, starting: volume(100), peak: volume(100))) == [100, 200])
    }

    @Test("input order does not matter; the result is in date order and carries phase and role")
    func ordering() throws {
        let result = try builder.targets(for: micros([.build, .build, .taper]).reversed(), starting: volume(100), peak: volume(200))
        #expect(result.map(\.microStart) == [day(0), day(7), day(14)])
        #expect(result.map(\.loadRole) == [.build, .build, .taper])
        #expect(result[0].id == day(0) && result[0].phase == .build)
    }

    @Test("distance and duration measures are carried through")
    func measures() throws {
        let result = try builder.targets(for: micros([.build, .build]), starting: volume(30_000, .distanceMeters), peak: volume(60_000, .distanceMeters))
        #expect(result.allSatisfy { $0.target.measure == .distanceMeters })
        #expect(amounts(result) == [30_000, 60_000])
    }

    @Test("a mismatched measure, a peak below the start and a bad fraction throw")
    func errors() {
        #expect(throws: VolumeCurveError.mismatchedMeasure) {
            try builder.targets(for: micros([.build]), starting: volume(100), peak: volume(200, .durationSeconds))
        }
        #expect(throws: VolumeCurveError.peakBelowStart) {
            try builder.targets(for: micros([.build]), starting: volume(200), peak: volume(100))
        }
        #expect(throws: VolumeCurveError.invalidFraction) {
            try VolumeCurveBuilder(recoveryLoadFraction: 0).targets(for: micros([.build]), starting: volume(100), peak: volume(200))
        }
        #expect(throws: VolumeCurveError.invalidFraction) {
            try VolumeCurveBuilder(recoveryLoadFraction: 1.2).targets(for: micros([.build]), starting: volume(100), peak: volume(200))
        }
        #expect(throws: VolumeCurveError.invalidFraction) {
            try VolumeCurveBuilder(taperStartFraction: 0.4, taperEndFraction: 0.6).targets(for: micros([.build]), starting: volume(100), peak: volume(200))
        }
        #expect(throws: VolumeCurveError.invalidFraction) {
            try VolumeCurveBuilder(raceFraction: .nan).targets(for: micros([.build]), starting: volume(100), peak: volume(200))
        }
    }

    @Test("the length of a micro across a daylight-saving change is whole days")
    func daylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 25))!
        let end = calendar.date(byAdding: .day, value: 6, to: start)! // spans the 29 March change
        let micro = Microcycle(dateRange: start...end, phase: .build, loadRole: .build, mesoBlockIndex: 0)
        let result = try builder.targets(for: [micro], starting: volume(100), peak: volume(100))
        #expect(result[0].lengthDays == 7 && result[0].target.amount == 100)
    }

    @Test("a laid-out plan ends in a taper micro that gets the race fraction and stays out of the taper ramp")
    func laidOutRaceMicro() throws {
        let macro = MacroTemplate(name: "Block", mesoBlocks: [
            MacroTemplate.MesoBlock(phase: .build, microCount: 4),
            MacroTemplate.MesoBlock(phase: .taper, microCount: 3),
        ])
        let athlete = AthleteProfile.fixture()
        let raceDay = Date(timeIntervalSince1970: 1_700_000_000)
        let race = Race(name: "Goal", date: raceDay, priority: .primary, distanceMeters: 10_000)
        let layout = CycleLayoutBuilder().microcycles(from: raceDay.addingTimeInterval(-60 * 86400), to: race, macro: macro, meso: .linear, athlete: athlete)
        #expect(layout.map(\.loadRole) == [.build, .build, .build, .build, .taper, .taper, .taper])
        let result = try builder.targets(for: layout, starting: volume(100), peak: volume(200))
        // Peak 200: taper ramp 0.7 to 0.5 over the two taper micros before race week, then 0.3.
        #expect(amounts(result).suffix(3) == [140, 100, 60])
    }
}
