import Foundation
import Testing
@testable import TrainingCore

@Suite("LeadTimeCompromiser")
struct LeadTimeCompromiserTests {
    private let compromiser = LeadTimeCompromiser()
    private let wantsConditioning = PlanPreferences(includeConditioning: true)

    /// conditioning 2, base 4, structural 6, specific 6, taper 2: 20 micros.
    private let triphasic = MacroTemplate(name: "Triphasic", mesoBlocks: [
        .init(phase: .conditioning, microCount: 2),
        .init(phase: .base, microCount: 4),
        .init(phase: .structural, microCount: 6),
        .init(phase: .specific, microCount: 6),
        .init(phase: .taper, microCount: 2),
    ])

    /// base 4, build 6, peak 4, taper 2: 16 micros.
    private let polarized = MacroTemplate(name: "Polarized", mesoBlocks: [
        .init(phase: .base, microCount: 4),
        .init(phase: .build, microCount: 6),
        .init(phase: .peak, microCount: 4),
        .init(phase: .taper, microCount: 2),
    ])

    private func adjust(
        _ macro: MacroTemplate,
        _ paradigm: TrainingParadigm = .triphasic,
        micros: Int,
        length: Int = 7,
        extraDays: Int = 0,
        preferences: PlanPreferences,
        using compromiser: LeadTimeCompromiser? = nil
    ) throws -> LeadTimeAdjustment {
        try (compromiser ?? self.compromiser).adjust(macro, paradigm: paradigm, leadTimeDays: micros * length + extraDays, microLengthDays: length, preferences: preferences)
    }

    private func counts(_ adjustment: LeadTimeAdjustment) -> [String: Int] {
        Dictionary(adjustment.macro.mesoBlocks.map { ($0.phase.id, $0.microCount) }, uniquingKeysWith: +)
    }

    @Test("a lead time that fits leaves the macro and reports nothing")
    func fullLeadTime() throws {
        let result = try adjust(triphasic, micros: 20, preferences: wantsConditioning)

        #expect(result.macro == triphasic)
        #expect(result.compromises.isEmpty)
        #expect(try adjust(triphasic, micros: 30, preferences: wantsConditioning).macro == triphasic)
    }

    @Test("without the conditioning preference the phase is left out, and that is not a compromise")
    func conditioningOptedOut() throws {
        let result = try adjust(triphasic, micros: 20, preferences: PlanPreferences())

        #expect(counts(result)["conditioning"] == nil)
        #expect(result.macro.mesoBlocks.map(\.phase) == [.base, .structural, .specific, .taper])
        #expect(result.compromises.isEmpty)
    }

    @Test("conditioning goes first and reports the overridden preference")
    func conditioningDropped() throws {
        let result = try adjust(triphasic, micros: 18, preferences: wantsConditioning)

        #expect(result.macro.mesoBlocks.map(\.phase) == [.base, .structural, .specific, .taper])
        #expect(result.compromises == [
            LeadTimeCompromise(action: .phaseDropped(.conditioning), reason: .leadTimeTooShort(availableMicros: 18, neededMicros: 20)),
        ])
        #expect(result.compromises[0].overriddenPreference == .includeConditioning)
    }

    @Test("structural is dropped next")
    func structuralDropped() throws {
        let result = try adjust(triphasic, micros: 12, preferences: wantsConditioning)

        #expect(counts(result) == ["base": 4, "specific": 6, "taper": 2])
        #expect(result.compromises.map(\.action) == [.phaseDropped(.conditioning), .phaseDropped(.structural)])
        #expect(result.compromises[1].reason == .leadTimeTooShort(availableMicros: 12, neededMicros: 18))
        #expect(result.compromises[1].overriddenPreference == nil)
    }

    @Test("specific is shortened after structural, base kept")
    func specificShortened() throws {
        let result = try adjust(triphasic, micros: 10, preferences: PlanPreferences())

        #expect(counts(result) == ["base": 4, "specific": 4, "taper": 2])
        #expect(result.compromises.map(\.action) == [
            .phaseDropped(.structural),
            .phaseShortened(.specific, fromMicros: 6, toMicros: 4),
        ])
    }

    @Test("specific stops at the minimum, then the oldest blocks are trimmed")
    func oldestTrimmed() throws {
        let result = try adjust(triphasic, micros: 5, preferences: PlanPreferences())

        #expect(counts(result) == ["base": 2, "specific": 1, "taper": 2])
        #expect(result.compromises.map(\.action) == [
            .phaseDropped(.structural),
            .phaseShortened(.specific, fromMicros: 6, toMicros: 1),
            .oldestPhaseTrimmed(.base, fromMicros: 4, toMicros: 2),
        ])
        #expect(result.macro.mesoBlocks.reduce(0) { $0 + $1.microCount } == 5)
    }

    @Test("a trimmed block that is cut to nothing is removed")
    func trimmedToNothing() throws {
        let result = try adjust(triphasic, micros: 3, preferences: PlanPreferences())

        #expect(result.macro.mesoBlocks.map(\.phase) == [.specific, .taper])
        #expect(result.compromises.last?.action == .oldestPhaseTrimmed(.base, fromMicros: 4, toMicros: 0))
    }

    @Test("the taper plus the shortest specific is the limit; below it there is no plan")
    func belowMinimum() throws {
        #expect(try adjust(triphasic, micros: 3, preferences: PlanPreferences()).macro.mesoBlocks.map(\.microCount) == [1, 2])
        #expect(throws: LeadTimeError.leadTimeTooShort(availableMicros: 2, requiredMicros: 3)) {
            try adjust(triphasic, micros: 2, preferences: PlanPreferences())
        }
        #expect(throws: LeadTimeError.leadTimeTooShort(availableMicros: 0, requiredMicros: 3)) {
            try adjust(triphasic, micros: 0, preferences: PlanPreferences())
        }
    }

    @Test("the minimum is a parameter and never negative")
    func minimumParameter() throws {
        let strict = LeadTimeCompromiser(minimumShortenedMicros: 3)

        #expect(try adjust(triphasic, micros: 6, preferences: PlanPreferences(), using: strict).macro.mesoBlocks.map(\.microCount) == [1, 3, 2])
        #expect(throws: LeadTimeError.leadTimeTooShort(availableMicros: 4, requiredMicros: 5)) {
            try adjust(triphasic, micros: 4, preferences: PlanPreferences(), using: strict)
        }
        #expect(LeadTimeCompromiser(minimumShortenedMicros: -2).minimumShortenedMicros == 0)
        #expect(try adjust(triphasic, micros: 2, preferences: PlanPreferences(), using: LeadTimeCompromiser(minimumShortenedMicros: 0)).macro.mesoBlocks.map(\.phase) == [.taper])
    }

    @Test("micro length turns days into whole micros; the remainder is not planned", arguments: [7, 10, 14])
    func microLengths(length: Int) throws {
        let result = try adjust(triphasic, micros: 12, length: length, extraDays: length - 1, preferences: PlanPreferences())

        #expect(counts(result) == ["base": 4, "specific": 6, "taper": 2])
        #expect(result.compromises.map(\.action) == [.phaseDropped(.structural)])
        #expect(result.compromises[0].reason == .leadTimeTooShort(availableMicros: 12, neededMicros: 18))
        #expect(try adjust(triphasic, micros: 12, length: length, preferences: PlanPreferences()).macro == result.macro)
    }

    @Test("polarized shortens peak, then trims the oldest blocks")
    func polarizedShortensPeak() throws {
        let shortened = try adjust(polarized, .polarized8020, micros: 14, preferences: PlanPreferences())
        #expect(counts(shortened) == ["base": 4, "build": 6, "peak": 2, "taper": 2])
        #expect(shortened.compromises.map(\.action) == [.phaseShortened(.peak, fromMicros: 4, toMicros: 2)])

        let trimmed = try adjust(polarized, .polarized8020, micros: 6, preferences: PlanPreferences())
        #expect(counts(trimmed) == ["build": 3, "peak": 1, "taper": 2])
        #expect(trimmed.compromises.map(\.action) == [
            .phaseShortened(.peak, fromMicros: 4, toMicros: 1),
            .oldestPhaseTrimmed(.base, fromMicros: 4, toMicros: 0),
            .oldestPhaseTrimmed(.build, fromMicros: 6, toMicros: 3),
        ])
    }

    @Test("a paradigm without a shortenable phase only trims the oldest blocks, keeping the taper")
    func noShortenablePhase() throws {
        let paradigm = TrainingParadigm(name: "Plain", phases: [.base, .build, .peak, .taper])
        let result = try adjust(polarized, paradigm, micros: 5, preferences: PlanPreferences())

        #expect(counts(result) == ["peak": 3, "taper": 2])
        #expect(result.compromises.map(\.action) == [
            .oldestPhaseTrimmed(.base, fromMicros: 4, toMicros: 0),
            .oldestPhaseTrimmed(.build, fromMicros: 6, toMicros: 0),
            .oldestPhaseTrimmed(.peak, fromMicros: 4, toMicros: 3),
        ])
        #expect(throws: LeadTimeError.leadTimeTooShort(availableMicros: 1, requiredMicros: 2)) {
            try adjust(polarized, paradigm, micros: 1, preferences: PlanPreferences())
        }
    }

    @Test("bad inputs throw")
    func invalidInput() {
        #expect(throws: LeadTimeError.invalidMicroLength) {
            try compromiser.adjust(triphasic, paradigm: .triphasic, leadTimeDays: 70, microLengthDays: 0, preferences: PlanPreferences())
        }
        #expect(throws: LeadTimeError.negativeLeadTime) {
            try compromiser.adjust(triphasic, paradigm: .triphasic, leadTimeDays: -1, microLengthDays: 7, preferences: PlanPreferences())
        }
    }

    @Test("an adjusted macro lays out from the race back without further trimming")
    func laysOut() throws {
        let athlete = AthleteProfile.fixture()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let raceDate = calendar.date(from: DateComponents(year: 2027, month: 4, day: 25))!
        let race = Race(name: "Marathon", date: raceDate, priority: .primary, distanceMeters: 42_195)
        let start = calendar.date(byAdding: .day, value: -(10 * 7 - 1), to: raceDate)!
        let adjusted = try adjust(triphasic, micros: 10, preferences: PlanPreferences())

        let micros = CycleLayoutBuilder().microcycles(from: start, to: race, macro: adjusted.macro, meso: MesocycleTemplate(name: "3:1", microRoles: [.build], microLengthDays: 7), athlete: athlete)

        #expect(micros.count == 10)
        #expect(micros.first?.dateRange.lowerBound == calendar.startOfDay(for: start))
    }

    @Test("compromises round-trip")
    func codable() throws {
        let result = try adjust(triphasic, micros: 5, preferences: wantsConditioning)

        let decoded = try JSONDecoder().decode(LeadTimeAdjustment.self, from: JSONEncoder().encode(result))

        #expect(decoded == result)
    }
}

@Suite("includeConditioning and shortenablePhase")
struct ConditioningSettingTests {
    @Test("includeConditioning defaults to false and round-trips")
    func preference() throws {
        #expect(PlanPreferences().includeConditioning == false)
        let preferences = PlanPreferences(includeConditioning: true)

        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: JSONEncoder().encode(preferences))

        #expect(decoded == preferences)
    }

    @Test("a stored payload without it, or with a bad value, reads as false")
    func legacyPreferences() throws {
        #expect(try JSONDecoder().decode(PlanPreferences.self, from: Data(#"{"runAvailability":{}}"#.utf8)).includeConditioning == false)
        #expect(try JSONDecoder().decode(PlanPreferences.self, from: Data(#"{"includeConditioning":"yes"}"#.utf8)).includeConditioning == false)
    }

    @Test("the built-in paradigms name their shortenable phase; stored paradigms without it decode to none")
    func paradigm() throws {
        #expect(TrainingParadigm.triphasic.shortenablePhase == .specific)
        #expect(TrainingParadigm.polarized8020.shortenablePhase == .peak)
        #expect(try JSONDecoder().decode(TrainingParadigm.self, from: Data(#"{"name":"Old"}"#.utf8)).shortenablePhase == nil)
        let decoded = try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(TrainingParadigm.triphasic))
        #expect(decoded == .triphasic)
    }
}
