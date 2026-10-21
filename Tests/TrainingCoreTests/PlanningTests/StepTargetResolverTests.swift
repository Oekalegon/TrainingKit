import Foundation
import Testing
@testable import TrainingCore

@Suite("StepTargetResolver")
struct StepTargetResolverTests {
    // Rest 50, max 190 (Karvonen), threshold pace 240 s/km: zone 4 is 162...176 bpm, 230.4...249.6 s/km.
    let athlete = AthleteProfile.fixture()
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    func workout(_ steps: [WorkoutStep]) -> StructuredWorkout {
        StructuredWorkout(name: "Test", sport: .running, blocks: [WorkoutBlock(steps: steps)])
    }

    func resolve(
        _ steps: [WorkoutStep], athlete: AthleteProfile? = nil, race: SpecificPhaseTarget? = .pace(secondsPerKilometer: 240), fraction: Double? = nil
    ) -> StepTargetResolution {
        StepTargetResolver.resolve(workout(steps), on: date, athlete: athlete ?? self.athlete, raceTarget: race, raceTargetFraction: fraction)
    }

    func step(_ kind: StepKind = .work, target: IntensityTarget?) -> WorkoutStep {
        WorkoutStep(kind: kind, goal: .time(300), target: target)
    }

    @Test("a zone step gets the zone's bpm range and pace range")
    func zoneStep() {
        let result = resolve([step(target: .heartRateZone(4))])
        let resolved = result.workout.blocks[0].steps[0]
        #expect(resolved.target == .heartRateRange(162, 176))
        guard case .pace(let pace)? = resolved.companionTarget else { Issue.record("no pace"); return }
        #expect(abs(pace.lowerBound - 230.4) < 1e-9 && abs(pace.upperBound - 249.6) < 1e-9)
        #expect(result.unresolved.isEmpty)
    }

    @Test("every zone resolves, and neighbouring zones share a boundary")
    func zoneBoundaries() {
        let model = HeartRateZoneModel(settings: athlete.currentHeartRateZoneSettings!)
        var previous: (bpm: ClosedRange<Double>, pace: ClosedRange<Double>)?
        for zone in 1...5 {
            let resolved = resolve([step(target: .heartRateZone(zone))]).workout.blocks[0].steps[0]
            guard case .heartRateRange(let low, let high)? = resolved.target, case .pace(let pace)? = resolved.companionTarget else {
                Issue.record("zone \(zone) not resolved"); return
            }
            #expect(low...high == model.zoneBPMRange(zone))
            if let previous {
                #expect(abs(previous.bpm.upperBound - low) < 1e-9)
                #expect(abs(previous.pace.lowerBound - pace.upperBound) < 1e-9)
            }
            previous = (low...high, pace)
        }
    }

    @Test("zones follow the date: the settings in effect on the date are used")
    func dateEffectiveZones() {
        var athlete = athlete
        let later = date.addingTimeInterval(86_400 * 30)
        athlete.heartRateZoneHistory.append(HeartRateZoneSettings(effectiveDate: later, restingHeartRateBPM: 60, maxHeartRateBPM: 180))
        athlete.paceHistory.append(PaceSettings(effectiveDate: later, paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300)))
        let workout = workout([step(target: .heartRateZone(4))])
        let before = StepTargetResolver.resolve(workout, on: date, athlete: athlete, raceTarget: nil, raceTargetFraction: nil)
        let after = StepTargetResolver.resolve(workout, on: later, athlete: athlete, raceTarget: nil, raceTargetFraction: nil)
        #expect(before.workout.blocks[0].steps[0].target == .heartRateRange(162, 176))
        #expect(after.workout.blocks[0].steps[0].target == .heartRateRange(156, 168))
        guard case .pace(let pace)? = after.workout.blocks[0].steps[0].companionTarget else { Issue.record("no pace"); return }
        #expect(abs(pace.lowerBound - 288) < 1e-9)
    }

    @Test("a work step with no target takes the fraction of the race pace; above one is faster")
    func fractionOfSpeed() {
        func pace(_ fraction: Double) -> ClosedRange<Double> {
            guard case .pace(let range)? = resolve([step(target: nil)], fraction: fraction).workout.blocks[0].steps[0].target else {
                Issue.record("no pace for \(fraction)"); return 0...0
            }
            return range
        }
        let fast = pace(1.05), slow = pace(0.9), same = pace(1)
        #expect(abs((fast.lowerBound + fast.upperBound) / 2 - 240 / 1.05) < 1e-9)
        #expect(abs((slow.lowerBound + slow.upperBound) / 2 - 240 / 0.9) < 1e-9)
        #expect(abs(same.lowerBound - 235.2) < 1e-9 && abs(same.upperBound - 244.8) < 1e-9)
        #expect(fast.upperBound < same.lowerBound && slow.lowerBound > same.upperBound)
    }

    @Test("a zone step shows the phase pace when it falls in the zone")
    func phasePaceInZone() {
        let result = resolve([step(target: .heartRateZone(4))], fraction: 0.98)
        let resolved = result.workout.blocks[0].steps[0]
        #expect(resolved.target == .heartRateRange(162, 176))
        guard case .pace(let pace)? = resolved.companionTarget else { Issue.record("no pace"); return }
        #expect(abs((pace.lowerBound + pace.upperBound) / 2 - 240 / 0.98) < 1e-9)
        #expect(result.unresolved.isEmpty)
    }

    @Test("a phase pace outside the step's zone is reported and the zone's own pace kept")
    func phasePaceOutsideZone() {
        // 240 / 0.8 = 300 s/km, a zone 2 pace.
        let model = athlete.paceModel
        let slow = resolve([step(target: .heartRateZone(4))], fraction: 0.8)
        let expectedZone = (1...5).first { StepTargetResolver.paceRange(zone: $0, in: model)!.contains(300) }
        #expect(expectedZone == 2)
        #expect(slow.unresolved == [UnresolvedStep(blockIndex: 0, stepIndex: 0, reason: .paceOutsideZone(zone: 4, paceZone: expectedZone))])
        #expect(slow.workout.blocks[0].steps[0].target == .heartRateRange(162, 176))
        #expect(slow.workout.blocks[0].steps[0].companionTarget == .pace(StepTargetResolver.paceRange(zone: 4, in: model)!))
        // Faster than every zone.
        let fast = resolve([step(target: .heartRateZone(4))], fraction: 1.4)
        #expect(fast.unresolved.first?.reason == .paceOutsideZone(zone: 4, paceZone: nil))
    }

    @Test("only work steps use the phase pace")
    func warmupIgnoresPhase() {
        let result = resolve([step(.warmup, target: .heartRateZone(1)), step(.cooldown, target: nil)], fraction: 1.05)
        #expect(result.unresolved.isEmpty)
        #expect(result.workout.blocks[0].steps[1].target == nil)
        #expect(result.workout.blocks[0].steps[0].companionTarget == .pace(StepTargetResolver.paceRange(zone: 1, in: athlete.paceModel)!))
    }

    @Test("no race target, or one that is not a pace, is reported and nothing is guessed")
    func missingRaceTarget() {
        let steps = [step(target: nil), step(target: .heartRateZone(4))]
        let races: [SpecificPhaseTarget?] = [nil, .heartRate(beatsPerMinute: 160...170), .perceivedEffort(7), .predictedFromFitness]
        for race in races {
            let result = resolve(steps, race: race, fraction: 1)
            let reason: UnresolvedReason = race == nil ? .noRaceTarget : .unsupportedRaceTarget
            #expect(result.unresolved.map(\.reason) == [reason, reason])
            #expect(result.workout.blocks[0].steps[0].target == nil)
            #expect(result.workout.blocks[0].steps[1].target == .heartRateRange(162, 176))
        }
    }

    @Test("without a fraction the race target is not consulted")
    func noFraction() {
        let result = resolve([step(target: nil)], race: nil, fraction: nil)
        #expect(result.unresolved.isEmpty && result.workout.blocks[0].steps[0].target == nil)
        #expect(resolve([step(target: nil)], fraction: 0).workout.blocks[0].steps[0].target == nil)
    }

    @Test("no zones, an unavailable zone method or a bad zone is reported")
    func noZones() {
        var bare = athlete
        bare.heartRateZoneHistory = []
        let none = resolve([step(target: .heartRateZone(3))], athlete: bare)
        #expect(none.unresolved.map(\.reason) == [.noHeartRateZones])
        #expect(none.workout.blocks[0].steps[0].target == .heartRateZone(3))
        let noThreshold = AthleteProfile.fixture(zoneMethod: .lactateThreshold)
        #expect(resolve([step(target: .heartRateZone(3))], athlete: noThreshold).unresolved.map(\.reason) == [.zoneUnavailable(3)])
        #expect(resolve([step(target: .heartRateZone(9))]).unresolved.map(\.reason) == [.zoneUnavailable(9)])
    }

    @Test("explicit pace, power, range and RPE targets are kept")
    func explicitKept() {
        let targets: [IntensityTarget] = [.pace(240...250), .power(200...220), .heartRateRange(150, 160), .rpe(7)]
        let result = resolve(targets.map { step(target: $0) }, fraction: 1.1)
        #expect(result.workout.blocks[0].steps.map(\.target) == targets)
        #expect(result.workout.blocks[0].steps.allSatisfy { $0.companionTarget == nil })
        #expect(result.unresolved.isEmpty)
    }

    @Test("resolving keeps repetitions and the rest of the workout, and is idempotent")
    func structureKept() {
        let input = StructuredWorkout(name: "6x", sport: .running, blocks: [
            WorkoutBlock(steps: [step(.warmup, target: .heartRateZone(1))]),
            WorkoutBlock(steps: [step(target: .heartRateZone(4)), step(.recovery, target: .heartRateZone(1))], repetitions: 6),
        ])
        let race = SpecificPhaseTarget.pace(secondsPerKilometer: 240)
        let once = StepTargetResolver.resolve(input, on: date, athlete: athlete, raceTarget: race, raceTargetFraction: 1)
        #expect(once.workout.blocks[1].repetitions == 6 && once.workout.id == input.id)
        let twice = StepTargetResolver.resolve(once.workout, on: date, athlete: athlete, raceTarget: race, raceTargetFraction: 1)
        #expect(twice.workout == once.workout)
    }

    @Test("TRIMP load and duration agree before and after resolving")
    func agreesWithEstimators() {
        let steps = (1...5).map { zone in
            WorkoutStep(kind: .work, goal: zone.isMultiple(of: 2) ? .time(600) : .distance(2000), target: .heartRateZone(zone))
        }
        let input = workout(steps)
        let resolved = StepTargetResolver.resolve(input, on: date, athlete: athlete, raceTarget: nil, raceTargetFraction: nil).workout
        let estimator = TRIMPPlanEstimator()
        #expect(abs(estimator.estimatedLoad(for: input, athlete: athlete).value - estimator.estimatedLoad(for: resolved, athlete: athlete).value) < 1e-6)
        let durations = WorkoutDurationEstimator()
        #expect(abs(durations.duration(for: input, athlete: athlete) - durations.duration(for: resolved, athlete: athlete)) < 1e-6)
    }

    @Test("a step without a companion target decodes from an older payload")
    func tolerantDecoding() throws {
        let old = try JSONEncoder().encode(WorkoutStep(kind: .work, goal: .time(60), target: .rpe(5)))
        var object = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        object["companionTarget"] = nil
        let step = try JSONDecoder().decode(WorkoutStep.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(step.companionTarget == nil)
        let source = WorkoutStep(kind: .work, goal: .time(60), target: .rpe(5), companionTarget: .pace(200...210))
        #expect(try JSONDecoder().decode(WorkoutStep.self, from: JSONEncoder().encode(source)) == source)
    }
}
