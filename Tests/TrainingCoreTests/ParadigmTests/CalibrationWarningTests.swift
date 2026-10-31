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

    /// Triphasic without the profiles per distance (MVP5-154): its marathon numbers used for every race, so it warns.
    private static var marathonOnly: TrainingParadigm {
        var paradigm = TrainingParadigm.triphasic
        paradigm.distanceProfiles = [:]
        return paradigm
    }

    @Test("triphasic is calibrated for the marathon, polarized for nothing")
    func builtIns() {
        #expect(TrainingParadigm.triphasic.calibratedDistanceMeters == Race.marathonDistanceMeters)
        #expect(TrainingParadigm.polarized8020.calibratedDistanceMeters == nil)
    }

    @Test("a 5K, a 10K and a half marathon warn, carrying both distances")
    func shorterRaces() {
        for meters in [5_000.0, 10_000, 21_097.5] {
            let warning = Self.marathonOnly.calibrationWarning(for: race(meters))
            #expect(warning == CalibrationWarning(raceDistanceMeters: meters, calibratedDistanceMeters: 42_195))
        }
    }

    @Test("triphasic has profiles for a 5K, a 10K and a half marathon, so it does not warn for them (MVP5-154)")
    func shorterRacesHaveProfiles() {
        for meters in [5_000.0, 10_000, 21_097.5, 7_500, 15_000, 30_000] {
            #expect(TrainingParadigm.triphasic.calibrationWarning(for: race(meters)) == nil)
        }
        // A 35 km race has no class and is not a marathon either.
        #expect(TrainingParadigm.triphasic.calibrationWarning(for: race(35_000)) != nil)
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
        let proposal = try await PlanAdjuster(paradigm: Self.marathonOnly, targetRace: target)
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
        #expect(decoded.distanceProfiles == TrainingParadigm.triphasic.distanceProfiles)
        #expect(legacy.distanceProfiles.isEmpty)
    }

    @Test("a proposal stored before the warning decodes without one")
    func legacyProposal() async throws {
        let proposal = try await PlanAdjuster(paradigm: Self.marathonOnly, targetRace: race(5_000)).propose(using: FlatProvider(), today: FlatProvider.start)
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
        var paradigm = TrainingParadigm.triphasic
        paradigm.distanceProfiles = [:]
        let proposal = try await PlanAdjuster(paradigm: paradigm, targetRace: race).propose(using: FlatProvider(), today: FlatProvider.start)
        let preview = PlanPreview(proposal: proposal, replacedPlan: nil, replacedActivities: [], replacedPlanIsFollowed: false)
        #expect(preview.calibrationWarning == CalibrationWarning(raceDistanceMeters: 10_000, calibratedDistanceMeters: 42_195))
    }
}

@Suite("Race distance classes (MVP5-154)")
struct RaceDistanceClassTests {
    @Test("a race is put in the class of the nearest distance; above 30 km, and no distance, have none")
    func classes() {
        #expect(RaceDistanceClass(distanceMeters: 5_000) == .fiveK)
        #expect(RaceDistanceClass(distanceMeters: 7_500) == .fiveK)
        #expect(RaceDistanceClass(distanceMeters: 7_501) == .tenK)
        #expect(RaceDistanceClass(distanceMeters: 10_000) == .tenK)
        #expect(RaceDistanceClass(distanceMeters: 15_000) == .tenK)
        #expect(RaceDistanceClass(distanceMeters: 21_097.5) == .halfMarathon)
        #expect(RaceDistanceClass(distanceMeters: 30_000) == .halfMarathon)
        #expect(RaceDistanceClass(distanceMeters: 42_195) == nil)
        #expect(RaceDistanceClass(distanceMeters: 100_000) == nil)
        #expect(RaceDistanceClass(distanceMeters: 0) == nil)
        #expect(RaceDistanceClass(distanceMeters: .nan) == nil)
    }

    @Test("resolved(for:) takes the profiles of the race's class, and keeps the marathon's for a marathon, an ultra and no race")
    func resolvedProfiles() {
        func race(_ meters: Double) -> Race {
            Race(name: "R", date: Date(timeIntervalSince1970: 1_800_000_000), priority: .primary, distanceMeters: meters)
        }
        let paradigm = TrainingParadigm.triphasic
        for (meters, kind) in [(5_000.0, RaceDistanceClass.fiveK), (10_000, .tenK), (21_097.5, .halfMarathon)] {
            #expect(paradigm.resolved(for: race(meters)).sessionProfiles == paradigm.distanceProfiles[kind])
        }
        for target in [race(42_195), race(100_000), nil] {
            #expect(paradigm.resolved(for: target).sessionProfiles == paradigm.sessionProfiles)
        }
    }

    @Test("race-pace work is only in the specific phase and the taper; the base has hill sprints only")
    func racePaceOnlyWhereDecided() throws {
        for (kind, phases) in TrainingParadigm.triphasic.distanceProfiles {
            #expect(Set(phases.keys) == [.base, .structural, .specific, .taper], "\(kind)")
            let base = try #require(phases[.base])
            #expect(base.allSatisfy { $0.sessionType == .hillRepeats && $0.raceTargetFraction == nil })
            for profile in try #require(phases[.structural]) {
                let fractions = [profile.raceTargetFraction, profile.endRaceTargetFraction].compactMap { $0 }
                #expect(fractions.allSatisfy { abs($0 - 1) > 0.01 }, "\(kind): structural work is not at race pace")
            }
            for profile in (phases[.taper] ?? []) { #expect(profile.raceTargetFraction == 1.0) }
        }
    }

    @Test("a paradigm with profiles per distance round-trips; an unknown class or profile is skipped")
    func coding() throws {
        let decoded = try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(TrainingParadigm.triphasic))
        #expect(decoded == TrainingParadigm.triphasic)
        let json = #"{"name":"X","distanceProfiles":{"fiveK":{"specific":[{"sessionType":"interval"},{"sessionType":"nonsense"}]},"mile":{"specific":[]}}}"#
        let tolerant = try JSONDecoder().decode(TrainingParadigm.self, from: Data(json.utf8))
        #expect(tolerant.distanceProfiles == [.fiveK: [.specific: [SessionProfile(sessionType: .interval)]]])
    }
}
