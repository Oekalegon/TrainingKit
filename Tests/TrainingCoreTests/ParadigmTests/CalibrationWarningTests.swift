import Foundation
import Testing
@testable import TrainingCore

/// A provider with one micro and a flat, acceptable fitness series.
private struct FlatProvider: PlanCandidateProvider {
    static let start = Date(timeIntervalSince1970: 1_799_971_200)

    func candidate(levers: PlanLevers, today: Date) async throws -> PlanCandidate {
        let end = Self.start.addingTimeInterval(6 * 86400)
        let macro = TrainingCycle(level: .macro, phase: .build, name: "Macro", dateRange: Self.start...end)
        let micro = TrainingCycle(level: .micro, phase: .build, name: "Micro", dateRange: Self.start...end, parentID: macro.id)
        let metrics = (0..<7).map { index in
            FitnessMetrics(
                day: Self.start.addingTimeInterval(Double(index) * 86400), load: 50, ctl: 50, atl: 50, tsb: 0,
                monotony: .nan, strain: .nan, isProjected: true, isWarmingUp: false
            )
        }
        return PlanCandidate(cycles: [macro, micro], plannedActivities: [], sessions: [], metrics: metrics)
    }
}

@Suite("Calibration warning (MVP5-143)")
struct CalibrationWarningTests {
    private func race(_ meters: Double) -> Race {
        Race(name: "R", date: FlatProvider.start.addingTimeInterval(6 * 86400), priority: .primary, distanceMeters: meters)
    }

    @Test("triphasic is calibrated for the marathon, polarized for nothing")
    func builtIns() {
        #expect(TrainingParadigm.triphasic.calibratedDistanceMeters == Race.marathonDistanceMeters)
        #expect(TrainingParadigm.polarized8020.calibratedDistanceMeters == nil)
    }

    @Test("a 5K, a 10K and a half marathon warn, carrying both distances")
    func shorterRaces() {
        for meters in [5_000.0, 10_000, 21_097.5] {
            let warning = TrainingParadigm.triphasic.calibrationWarning(for: race(meters))
            #expect(warning == CalibrationWarning(raceDistanceMeters: meters, calibratedDistanceMeters: 42_195))
        }
    }

    @Test("a marathon, also a rounded one, does not warn")
    func marathon() {
        for meters in [42_195.0, 42_000, 42_500, 41_400, 43_000] {
            #expect(TrainingParadigm.triphasic.calibrationWarning(for: race(meters)) == nil)
        }
        // Just outside the 2 % tolerance below.
        #expect(TrainingParadigm.triphasic.calibrationWarning(for: race(41_300)) != nil)
    }

    @Test("an ultra and no race do not warn")
    func ultraAndNoRace() {
        #expect(TrainingParadigm.triphasic.calibrationWarning(for: race(50_000)) == nil)
        #expect(TrainingParadigm.triphasic.calibrationWarning(for: nil) == nil)
    }

    @Test("a paradigm without a calibration distance never warns")
    func uncalibrated() {
        #expect(TrainingParadigm.polarized8020.calibrationWarning(for: race(5_000)) == nil)
        #expect(TrainingParadigm(name: "X", calibratedDistanceMeters: 10_000).calibrationWarning(for: race(5_000)) != nil)
        #expect(TrainingParadigm(name: "X", calibratedDistanceMeters: -1).calibratedDistanceMeters == nil)
    }

    @Test("the proposal carries the warning for a 5K and stays acceptable")
    func proposalWarns() async throws {
        let target = race(5_000)
        let proposal = try await PlanAdjuster(paradigm: .triphasic, targetRace: target)
            .propose(using: FlatProvider(), today: FlatProvider.start)
        #expect(proposal.calibrationWarning == CalibrationWarning(raceDistanceMeters: 5_000, calibratedDistanceMeters: 42_195))
        #expect(proposal.isAcceptable)
        #expect(proposal.outcome == .acceptable)
        #expect(proposal.risks.isEmpty)
    }

    @Test("the proposal has no warning for a marathon, polarized, or no race")
    func proposalQuiet() async throws {
        let marathon = try await PlanAdjuster(paradigm: .triphasic, targetRace: race(42_195)).propose(using: FlatProvider(), today: FlatProvider.start)
        let polarized = try await PlanAdjuster(paradigm: .polarized8020, targetRace: race(5_000)).propose(using: FlatProvider(), today: FlatProvider.start)
        let none = try await PlanAdjuster(paradigm: .triphasic).propose(using: FlatProvider(), today: FlatProvider.start)
        #expect(marathon.calibrationWarning == nil)
        #expect(polarized.calibrationWarning == nil)
        #expect(none.calibrationWarning == nil)
    }

    @Test("a paradigm stored before the field decodes without one; the field round-trips")
    func coding() throws {
        let legacy = try JSONDecoder().decode(TrainingParadigm.self, from: Data(#"{"name":"Triphasic"}"#.utf8))
        #expect(legacy.calibratedDistanceMeters == nil)
        let decoded = try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(TrainingParadigm.triphasic))
        #expect(decoded.calibratedDistanceMeters == 42_195)
    }

    @Test("a proposal stored before the warning decodes without one")
    func legacyProposal() async throws {
        let proposal = try await PlanAdjuster(paradigm: .triphasic, targetRace: race(5_000)).propose(using: FlatProvider(), today: FlatProvider.start)
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(proposal)) as? [String: Any])
        #expect(object["calibrationWarning"] != nil)
        object["calibrationWarning"] = nil
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let legacy = try decoder.decode(PlanProposal.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.calibrationWarning == nil)
        #expect(legacy.isAcceptable)
    }
}

@Suite("Calibration warning in the preview (MVP5-143)")
struct CalibrationWarningPreviewTests {
    @Test("the preview exposes the proposal's warning")
    func previewPassesThrough() async throws {
        let race = Race(name: "R", date: FlatProvider.start.addingTimeInterval(6 * 86400), priority: .primary, distanceMeters: 10_000)
        let proposal = try await PlanAdjuster(paradigm: .triphasic, targetRace: race).propose(using: FlatProvider(), today: FlatProvider.start)
        let preview = PlanPreview(proposal: proposal, replacedPlan: nil, replacedActivities: [], replacedPlanIsFollowed: false)
        #expect(preview.calibrationWarning == CalibrationWarning(raceDistanceMeters: 10_000, calibratedDistanceMeters: 42_195))
    }
}
