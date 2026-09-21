import Foundation
import Testing
@testable import TrainingCore

@Suite("PlannedIntensityClassifier")
struct PlannedIntensityClassifierTests {
    private let classifier = PlannedIntensityClassifier()
    private let athlete = AthleteProfile.fixture()

    private func step(_ kind: StepKind, minutes: Double, target: IntensityTarget?) -> WorkoutStep {
        WorkoutStep(kind: kind, goal: .time(minutes * 60), target: target)
    }

    private func workout(_ steps: [WorkoutStep], repetitions: Int = 1) -> StructuredWorkout {
        StructuredWorkout(name: "Test", sport: .running, blocks: [WorkoutBlock(steps: steps, repetitions: repetitions)])
    }

    private func assess(_ workout: StructuredWorkout, athlete: AthleteProfile? = nil) -> IntensityAssessment {
        classifier.assess(workout, athlete: athlete ?? self.athlete)
    }

    @Test("a 60 minute easy run in zone 2 is low")
    func easyRunIsLow() {
        let result = assess(workout([step(.work, minutes: 60, target: .heartRateZone(2))]))

        #expect(result.category == .low)
        #expect(result.source == .planned)
        #expect(result.confidence == .high)
    }

    @Test("a recovery run in zone 1 is very low")
    func recoveryRunIsVeryLow() {
        #expect(assess(workout([step(.work, minutes: 45, target: .heartRateZone(1))])).category == .veryLow)
    }

    @Test("a 2 hour long run with 12 minutes in zone 3 stays low")
    func longRunWithBriefTempoIsLow() {
        let result = assess(workout([
            step(.work, minutes: 108, target: .heartRateZone(2)),
            step(.work, minutes: 12, target: .heartRateZone(3)),
        ]))

        #expect(result.category == .low)
        #expect(result.moderateSeconds == 12 * 60)
    }

    @Test("a 90 minute run with a 20 minute fast finish in zone 3 is medium")
    func fastFinishIsMedium() {
        let result = assess(workout([
            step(.work, minutes: 70, target: .heartRateZone(2)),
            step(.work, minutes: 20, target: .heartRateZone(3)),
        ]))

        #expect(result.category == .medium)
    }

    @Test("a continuous tempo run in zone 3 is medium")
    func tempoRunIsMedium() {
        let result = assess(workout([
            step(.warmup, minutes: 10, target: .heartRateZone(1)),
            step(.work, minutes: 30, target: .heartRateZone(3)),
            step(.cooldown, minutes: 10, target: .heartRateZone(1)),
        ]))

        #expect(result.category == .medium)
        #expect(result.moderateSeconds == 30 * 60)
        #expect(result.hardSeconds == 0)
    }

    @Test("a continuous threshold run in zone 4 is high")
    func thresholdRunIsHigh() {
        let result = assess(workout([
            step(.warmup, minutes: 10, target: .heartRateZone(1)),
            step(.work, minutes: 20, target: .heartRateZone(4)),
            step(.cooldown, minutes: 10, target: .heartRateZone(1)),
        ]))

        #expect(result.category == .high)
        #expect(result.hardSeconds == 20 * 60)
    }

    @Test("interval work is high even though recoveries drag the session's average zone down")
    func intervalsAreHigh() {
        let result = assess(workout([
            step(.work, minutes: 3, target: .heartRateZone(4)),
            step(.recovery, minutes: 2, target: .heartRateZone(1)),
        ], repetitions: 5))

        #expect(result.category == .high)
        #expect(result.hardSeconds == 15 * 60)
    }

    @Test("a single 3 minute hill in zone 4 within a 60 minute run stays low")
    func singleHillStaysLow() {
        let result = assess(workout([
            step(.work, minutes: 30, target: .heartRateZone(2)),
            step(.work, minutes: 3, target: .heartRateZone(4)),
            step(.work, minutes: 27, target: .heartRateZone(2)),
        ]))

        #expect(result.category == .low)
    }

    @Test("a warm-up or cool-down never counts towards hard or moderate time, whatever its target")
    func edgeStepsAreCappedAtZoneTwo() {
        let result = assess(workout([
            step(.warmup, minutes: 15, target: .heartRateZone(4)),
            step(.work, minutes: 30, target: .heartRateZone(2)),
            step(.cooldown, minutes: 15, target: .heartRateZone(5)),
        ]))

        #expect(result.category == .low)
        #expect(result.hardSeconds == 0)
        #expect(result.moderateSeconds == 0)
    }

    @Test("a pace target near threshold pace resolves to zone 4")
    func paceTargetResolvesThroughPaceModel() {
        // The fixture's threshold pace is 240 s/km, which is exactly zone 4.
        let result = assess(workout([step(.work, minutes: 20, target: .pace(235...245))]))

        #expect(result.category == .high)
        #expect(result.confidence == .high)
    }

    @Test("a slow pace target resolves to an easy zone")
    func slowPaceTargetIsEasy() {
        // Zone 2 pace is 240 * 1.20 = 288 s/km.
        #expect(assess(workout([step(.work, minutes: 60, target: .pace(280...296))])).category == .low)
    }

    @Test("an RPE target maps through Borg CR10: 4-5 is tempo, 6-7 is threshold")
    func rpeTargetMapsToZones() {
        #expect(assess(workout([step(.work, minutes: 30, target: .rpe(5))])).category == .medium)
        #expect(assess(workout([step(.work, minutes: 20, target: .rpe(6))])).category == .high)
        #expect(assess(workout([step(.work, minutes: 45, target: .rpe(2))])).category == .veryLow)
    }

    @Test("a heart-rate range resolves through the athlete's zone model")
    func heartRateRangeResolvesThroughZoneModel() {
        // Karvonen with resting 50 / max 190: 155 bpm is ratio 0.75, inside zone 3 (0.70–0.80).
        let result = assess(workout([step(.work, minutes: 30, target: .heartRateRange(150, 160))]))

        #expect(result.category == .medium)
        #expect(result.confidence == .high)
    }

    @Test("a work step with no target defaults to tempo effort and lowers confidence")
    func untargetedWorkStepDefaultsToTempo() {
        let result = assess(workout([step(.work, minutes: 30, target: nil)]))

        #expect(result.category == .medium)
        #expect(result.confidence == .medium)
    }

    @Test("a power target is not resolvable and falls back to the step-kind default")
    func powerTargetFallsBack() {
        let result = assess(workout([step(.work, minutes: 30, target: .power(200...220))]))

        #expect(result.category == .medium)
        #expect(result.confidence == .medium)
    }

    @Test("an open-ended step lowers confidence")
    func openStepLowersConfidence() {
        let openWorkout = workout([WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))])

        #expect(assess(openWorkout).confidence == .medium)
    }

    @Test("without recorded zone settings, zone targets still classify and a heart-rate range falls back")
    func worksWithoutZoneSettings() {
        let bareAthlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: []
        )

        let zoneTarget = assess(workout([step(.work, minutes: 20, target: .heartRateZone(4))]), athlete: bareAthlete)
        let rangeTarget = assess(workout([step(.work, minutes: 20, target: .heartRateRange(150, 160))]), athlete: bareAthlete)

        #expect(zoneTarget.category == .high)
        #expect(zoneTarget.confidence == .high)
        #expect(rangeTarget.category == .medium)
        #expect(rangeTarget.confidence == .medium)
    }

    @Test("an empty workout is very low with low confidence")
    func emptyWorkout() {
        let result = assess(StructuredWorkout(name: "Empty", sport: .running, blocks: []))

        #expect(result.category == .veryLow)
        #expect(result.confidence == .low)
    }

    @Test("the built-in templates classify as expected with their default parameters")
    func builtInTemplates() throws {
        func category(_ template: WorkoutTemplate) throws -> IntensityCategory {
            let defaults = Dictionary(uniqueKeysWithValues: template.parameters.map { ($0.key, $0.defaultValue) })
            return assess(try template.instantiate(values: defaults)).category
        }

        #expect(try category(BuiltInWorkoutTemplates.recoveryRun) == .veryLow)
        #expect(try category(BuiltInWorkoutTemplates.easyRun) == .low)
        #expect(try category(BuiltInWorkoutTemplates.longRun) == .low)
        #expect(try category(BuiltInWorkoutTemplates.tempoRun) == .medium)
    }
}
