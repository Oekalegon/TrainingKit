import Foundation
import Testing
@testable import TrainingCore

@Suite("TrainingParadigm, Overrides and mix")
struct TrainingParadigmTests {
    @Test("a nil override leaves the default; a set one replaces it")
    func overridesApply() {
        let base = PlanGuardrails()
        #expect(PlanGuardrails.Overrides().applied(to: base) == base)

        let applied = PlanGuardrails.Overrides(minAcceptableTSB: -45, maxLongestRunIncreaseFraction: 0.15).applied(to: base)
        #expect(applied.minAcceptableTSB == -45)
        #expect(applied.maxLongestRunIncreaseFraction == 0.15)
        #expect(applied.maxMonotony == base.maxMonotony)
        #expect(applied.strainTrailingWindowDays == base.strainTrailingWindowDays)
    }

    @Test("a paradigm round-trips through Codable")
    func roundTrip() throws {
        let paradigm = TrainingParadigm(
            name: "Test",
            phases: ["base", "specific"],
            guardrailOverrides: .init(maxMonotony: 2.5),
            defaultMix: IntensityMix(intensityShares: [.low: 0.8, .high: 0.2]),
            phaseMixes: ["base": IntensityMix(intensityShares: [.high: 0], speedShares: [.max: 0.1], tolerance: 0.1)],
            hardIntensity: .medium,
            hardSpeed: .max,
            minDaysBetweenHardSessions: 2,
            maxHardSessionsPerMicro: [7: 2, 14: 4]
        )
        let decoded = try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(paradigm))
        #expect(decoded == paradigm)
    }

    @Test("a legacy payload with only a name decodes to defaults; unknown keys and names are ignored")
    func tolerantDecoding() throws {
        let minimal = try JSONDecoder().decode(TrainingParadigm.self, from: Data(#"{"name":"Old","future":1}"#.utf8))
        #expect(minimal == TrainingParadigm(name: "Old"))
        #expect(minimal.hardIntensity == .high && minimal.hardSpeed == nil)

        let mix = try JSONDecoder().decode(IntensityMix.self, from: Data(#"{"intensityShares":{"low":0.8,"nonsense":1,"high":0.2}}"#.utf8))
        #expect(mix.intensityShares == [.low: 0.8, .high: 0.2])
        #expect(mix.tolerance == 0.05)

        let overrides = try JSONDecoder().decode(PlanGuardrails.Overrides.self, from: Data("{}".utf8))
        #expect(overrides == PlanGuardrails.Overrides())
    }

    @Test("a session or paradigm stored before long-run spacing decodes with it off")
    func legacyLongRun() throws {
        let session = try JSONDecoder().decode(PlanSession.self, from: Data(#"{"day":0,"seconds":60,"intensity":1,"speed":"slow"}"#.utf8))
        #expect(!session.isLongRun)
        #expect(!TrainingParadigm(name: "Old").spacesLongRunsAsHard)
    }

    @Test("hardness reads the intensity threshold, and speed only when the paradigm sets hardSpeed")
    func hardness() {
        let day = Date(timeIntervalSince1970: 0)
        let sprints = PlanSession(day: day, seconds: 1800, intensity: .low, speed: .max)
        let tempo = PlanSession(day: day, seconds: 3600, intensity: .medium, speed: .moderate)
        #expect(!TrainingParadigm(name: "a").isHard(sprints))
        #expect(TrainingParadigm(name: "a", hardSpeed: .max).isHard(sprints))
        #expect(!TrainingParadigm(name: "a").isHard(tempo))
        #expect(TrainingParadigm(name: "a", hardIntensity: .medium).isHard(tempo))
    }

    @Test("speed levels order slow < moderate < fast < max and map from zones")
    func speedOrder() {
        #expect(SpeedLevel.slow < .moderate && SpeedLevel.moderate < .fast && SpeedLevel.fast < .max)
        #expect([1, 2, 3, 4, 5, 9].map(SpeedLevel.init(zone:)) == [.slow, .slow, .moderate, .fast, .max, .max])
    }

    @Test("hill sprints are low intensity but max speed; recoveries and warm-up do not count")
    func sprintsAreMaxSpeed() {
        let classifier = PlannedIntensityClassifier()
        let athlete = AthleteProfile.fixture()
        let sprints = StructuredWorkout(name: "Sprints", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(900), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [
                WorkoutStep(kind: .work, goal: .time(8), target: .rpe(10)),
                WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(1)),
            ], repetitions: 8),
        ])
        #expect(classifier.speedLevel(of: sprints, athlete: athlete) == .max)
        #expect(classifier.assess(sprints, athlete: athlete).category <= .low)

        let session = classifier.session(on: Date(timeIntervalSince1970: 0), for: sprints, athlete: athlete)
        #expect(session.speed == .max && session.seconds == 900 + 8 * 128)

        let easy = StructuredWorkout(name: "Easy", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(2))]),
        ])
        #expect(classifier.speedLevel(of: easy, athlete: athlete) == .slow)
    }
}
