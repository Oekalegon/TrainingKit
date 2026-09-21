import Foundation
import Testing
@testable import TrainingCore

/// Heart rate is simulated by ``SimulatedHeartRate``.
///
/// With the fixture athlete (Karvonen, resting 50 / max 190) the zones are: Z1 120–134 bpm,
/// Z2 134–148, Z3 148–162, Z4 162–176, Z5 176–190.
@Suite("PlanGuidedIntensityClassifier")
struct PlanGuidedIntensityClassifierTests {
    private let classifier = PlanGuidedIntensityClassifier()
    private let athlete = AthleteProfile.fixture()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private typealias Effort = SimulatedHeartRate.Effort

    private func minutes(_ minutes: Double, _ bpm: Double) -> Effort {
        (minutes * 60, bpm)
    }

    private func step(_ kind: StepKind, seconds: Double, zone: Int) -> WorkoutStep {
        WorkoutStep(kind: kind, goal: .time(seconds), target: .heartRateZone(zone))
    }

    private func workout(_ blocks: [WorkoutBlock]) -> StructuredWorkout {
        StructuredWorkout(name: "Test", sport: .running, blocks: blocks)
    }

    /// 10 min warm-up, `reps` × (`workSeconds` at zone 4/5, `recoverySeconds` at zone 1), 10 min cool-down.
    private func intervalWorkout(reps: Int, workSeconds: Double, recoverySeconds: Double, workZone: Int = 4) -> StructuredWorkout {
        workout([
            WorkoutBlock(steps: [step(.warmup, seconds: 600, zone: 1)]),
            WorkoutBlock(
                steps: [step(.work, seconds: workSeconds, zone: workZone), step(.recovery, seconds: recoverySeconds, zone: 1)],
                repetitions: reps
            ),
            WorkoutBlock(steps: [step(.cooldown, seconds: 600, zone: 1)]),
        ])
    }

    /// The effort profile matching `intervalWorkout`, with the work reps performed at `workBPM`.
    private func intervalProfile(reps: Int, workSeconds: Double, recoverySeconds: Double, workBPM: Double) -> [Effort] {
        var profile: [Effort] = [minutes(10, 130)]
        for _ in 0..<reps {
            profile += [(workSeconds, workBPM), (recoverySeconds, 125)]
        }
        profile.append(minutes(10, 125))
        return profile
    }

    private func activity(_ profile: [Effort], samplesFor: [Effort]? = nil) -> Activity {
        Activity(
            source: .testing,
            sport: .running,
            start: start,
            duration: profile.reduce(0) { $0 + $1.seconds },
            heartRate: SimulatedHeartRate.samples(samplesFor ?? profile, start: start)
        )
    }

    @Test("intervals performed as planned are high, blended, with high confidence")
    func intervalsAsPlanned() {
        let plan = intervalWorkout(reps: 5, workSeconds: 180, recoverySeconds: 120)
        let run = activity(intervalProfile(reps: 5, workSeconds: 180, recoverySeconds: 120, workBPM: 172))

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .high)
        #expect(result.source == .blended)
        #expect(result.confidence == .high)
    }

    @Test("short reps that heart rate alone would miss are high once the plan says they were meant")
    func shortRepsAreRecognisedThroughThePlan() {
        // 16 × 30 s at zone 5 is 8 minutes of hard work, but every rep is shorter than the
        // shortest excursion the heart-rate-only classifier will count.
        let plan = intervalWorkout(reps: 16, workSeconds: 30, recoverySeconds: 60, workZone: 5)
        let run = activity(intervalProfile(reps: 16, workSeconds: 30, recoverySeconds: 60, workBPM: 186))

        let heartRateOnly = PerformedIntensityClassifier().assess(run, athlete: athlete)
        let guided = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(guided.category == .high)
        #expect((heartRateOnly?.category ?? .veryLow) < .high)
    }

    @Test("planned intervals that were skipped are not credited")
    func skippedIntervalsAreNotCredited() {
        let plan = intervalWorkout(reps: 5, workSeconds: 180, recoverySeconds: 120)
        // The athlete ran the whole session at an easy, steady effort instead.
        let run = activity(intervalProfile(reps: 5, workSeconds: 180, recoverySeconds: 120, workBPM: 140))

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .low)
    }

    @Test("an interval rep that only reached tempo counts as tempo")
    func repsThatFellShortCountAtTheZoneReached() {
        let plan = intervalWorkout(reps: 5, workSeconds: 180, recoverySeconds: 120)
        // Zone 3 (155 bpm) instead of the planned zone 4: 15 minutes of tempo, no hard time.
        let run = activity(intervalProfile(reps: 5, workSeconds: 180, recoverySeconds: 120, workBPM: 155))

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .medium)
        #expect(result.hardSeconds == 0)
    }

    @Test("an easy run that turned into a hard effort moves up only one level")
    func unplannedEffortMovesOneLevel() {
        let plan = workout([WorkoutBlock(steps: [step(.work, seconds: 3600, zone: 2)])])
        // 25 of the 60 minutes were actually run at threshold.
        let run = activity([minutes(15, 140), minutes(25, 168), minutes(20, 140)])

        let measured = PerformedIntensityClassifier().assess(run, athlete: athlete)
        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(measured?.category == .high)
        #expect(result.category == .medium)
        #expect(result.source == .blended)
        #expect(result.confidence == .medium)
    }

    @Test("an easy run performed easily is low with high confidence")
    func easyRunAsPlanned() {
        let plan = workout([WorkoutBlock(steps: [step(.work, seconds: 3600, zone: 2)])])
        let run = activity([minutes(60, 140)])

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .low)
        #expect(result.confidence == .high)
    }

    @Test("a plan with a distance step is moved one level towards the measured category, in either direction")
    func distancePlanBlendsWithMeasured() {
        // 5 km at zone 4 pace is planned as a hard session, but the run was easy.
        let hardPlan = workout([WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(4))])])
        let easyRun = activity([minutes(25, 140)])

        let downgraded = classifier.assess(easyRun, workout: hardPlan, athlete: athlete)
        #expect(downgraded.category == .medium)
        #expect(downgraded.source == .blended)
        #expect(downgraded.confidence == .medium)

        // A planned easy long run of 10 km performed easily agrees.
        let easyPlan = workout([WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(10_000), target: .heartRateZone(2))])])
        let agreed = classifier.assess(activity([minutes(60, 140)]), workout: easyPlan, athlete: athlete)
        #expect(agreed.category == .low)
        #expect(agreed.confidence == .high)
    }

    @Test("without heart rate the planned category is returned with low confidence")
    func noHeartRateReturnsPlan() {
        let plan = intervalWorkout(reps: 5, workSeconds: 180, recoverySeconds: 120)
        let run = Activity(source: .manual, sport: .running, start: start, duration: 2700)

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .high)
        #expect(result.source == .planned)
        #expect(result.confidence == .low)
    }

    @Test("steps with no heart rate to check are taken at their planned zone, without high confidence")
    func unverifiableStepsKeepPlannedZone() {
        let plan = intervalWorkout(reps: 5, workSeconds: 180, recoverySeconds: 120)
        let profile = intervalProfile(reps: 5, workSeconds: 180, recoverySeconds: 120, workBPM: 172)
        // Heart rate was only recorded for the first 8 minutes, before the first rep.
        let run = Activity(
            source: .testing, sport: .running, start: start, duration: profile.reduce(0) { $0 + $1.seconds },
            heartRate: SimulatedHeartRate.samples([minutes(8, 130)], start: start)
        )

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .high)
        #expect(result.confidence == .medium)
    }

    @Test("a plan with no hard or tempo steps is verified trivially and measured heart rate agrees")
    func planWithoutQualityStepsIsVerified() {
        let plan = workout([WorkoutBlock(steps: [step(.work, seconds: 2700, zone: 1)])])
        let run = activity([minutes(45, 125)])

        let result = classifier.assess(run, workout: plan, athlete: athlete)

        #expect(result.category == .veryLow)
        #expect(result.confidence == .high)
    }
}
