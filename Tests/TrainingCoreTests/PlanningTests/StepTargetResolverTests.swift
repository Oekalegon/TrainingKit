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

    @Test("a zone step keeps its zone and gets the zone's pace range; the bpm comes when the workout is sent")
    func zoneStep() {
        let result = resolve([step(target: .heartRateZone(4))])
        let resolved = result.workout.blocks[0].steps[0]
        #expect(resolved.target == .heartRateZone(4))
        guard case .pace(let pace)? = resolved.companionTarget else { Issue.record("no pace"); return }
        #expect(abs(pace.lowerBound - 230.4) < 1e-9 && abs(pace.upperBound - 249.6) < 1e-9)
        #expect(result.unresolved.isEmpty)

        let sent = StepTargetResolver.resolveBPM(result.workout, on: date, athlete: athlete)
        #expect(sent.workout.blocks[0].steps[0].target == .heartRateRange(162, 176))
        #expect(sent.workout.blocks[0].steps[0].companionTarget == resolved.companionTarget)
        #expect(sent.unresolved.isEmpty)
    }

    @Test("zone positions: Z3.0-Z3.4 is the lower 40 % of zone 3, in bpm and in pace")
    func zonePositionStep() {
        // Zone 3 is 148...162 bpm and 249.6...270.4 s/km for the fixture athlete: 3.4 is 40 % up from the bottom.
        let result = resolve([step(target: .heartRateZoneRange(3.0...3.4))])
        let resolved = result.workout.blocks[0].steps[0]
        #expect(resolved.target == .heartRateZoneRange(3.0...3.4))
        let zone = StepTargetResolver.paceRange(zone: 3, in: athlete.paceModel)!
        guard case .pace(let pace)? = resolved.companionTarget else { Issue.record("no pace"); return }
        #expect(abs(pace.upperBound - zone.upperBound) < 1e-9)
        #expect(abs(pace.lowerBound - (zone.upperBound - 0.4 * (zone.upperBound - zone.lowerBound))) < 1e-9)
        #expect(result.unresolved.isEmpty)

        let sent = StepTargetResolver.resolveBPM(result.workout, on: date, athlete: athlete).workout.blocks[0].steps[0]
        guard case .heartRateRange(let low, let high)? = sent.target else { Issue.record("no bpm"); return }
        #expect(abs(low - 148) < 1e-9 && abs(high - (148 + 0.4 * 14)) < 1e-9)
    }

    @Test("a whole zone as positions, 3.0 to 4.0, has the zone's pace range")
    func wholeZonePaceAsPositions() {
        #expect(StepTargetResolver.paceRange(zonePositions: 3.0...4.0, in: athlete.paceModel) == StepTargetResolver.paceRange(zone: 3, in: athlete.paceModel))
    }

    @Test("positions outside 1.0 to 6.0 are reported, and the bpm conversion reports them too")
    func badPositions() {
        for bad in [0.5...2.0, 4.0...6.5] {
            let result = resolve([step(target: .heartRateZoneRange(bad))])
            #expect(result.unresolved.map(\.reason) == [.zoneUnavailable(Int(((bad.lowerBound + bad.upperBound) / 2).rounded(.down)))])
            let sent = StepTargetResolver.resolveBPM(result.workout, on: date, athlete: athlete)
            #expect(sent.workout.blocks[0].steps[0].target == .heartRateZoneRange(bad))
            #expect(sent.unresolved.count == 1)
        }
    }

    @Test("sending without zone settings keeps the zone target and reports it; other targets pass through")
    func resolveBPMEdges() {
        var bare = athlete
        bare.heartRateZoneHistory = []
        let steps = [step(target: .heartRateZone(3)), step(target: .heartRateZoneRange(3.0...3.4)), step(target: .pace(240...250)), step(target: .rpe(5)), step(target: nil)]
        let sent = StepTargetResolver.resolveBPM(workout(steps), on: date, athlete: bare)
        #expect(sent.workout.blocks[0].steps.map(\.target) == steps.map(\.target))
        #expect(sent.unresolved.map(\.reason) == [.noHeartRateZones, .noHeartRateZones])
        let ok = StepTargetResolver.resolveBPM(workout(steps), on: date, athlete: athlete)
        #expect(ok.workout.blocks[0].steps.dropFirst(2).map(\.target) == steps.dropFirst(2).map(\.target))
        // Idempotent: a second conversion changes nothing.
        #expect(StepTargetResolver.resolveBPM(ok.workout, on: date, athlete: athlete).workout == ok.workout)
    }

    @Test("every zone resolves, and neighbouring zones share a boundary")
    func zoneBoundaries() {
        let model = HeartRateZoneModel(settings: athlete.currentHeartRateZoneSettings!)
        var previous: (bpm: ClosedRange<Double>, pace: ClosedRange<Double>)?
        for zone in 1...5 {
            let planned = resolve([step(target: .heartRateZone(zone))]).workout
            let resolved = StepTargetResolver.resolveBPM(planned, on: date, athlete: athlete).workout.blocks[0].steps[0]
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
        // The plan keeps the zone; the heart rate follows the zones in effect on the day it is sent.
        #expect(before.workout.blocks[0].steps[0].target == .heartRateZone(4))
        #expect(StepTargetResolver.resolveBPM(before.workout, on: date, athlete: athlete).workout.blocks[0].steps[0].target == .heartRateRange(162, 176))
        #expect(StepTargetResolver.resolveBPM(before.workout, on: later, athlete: athlete).workout.blocks[0].steps[0].target == .heartRateRange(156, 168))
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
        #expect(resolved.target == .heartRateZone(4))
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
        #expect(slow.workout.blocks[0].steps[0].target == .heartRateZone(4))
        #expect(slow.workout.blocks[0].steps[0].companionTarget == .pace(StepTargetResolver.paceRange(zone: 4, in: model)!))
        // Faster than every zone.
        let fast = resolve([step(target: .heartRateZone(4))], fraction: 1.4)
        #expect(fast.unresolved.first?.reason == .paceOutsideZone(zone: 4, paceZone: nil))
    }

    // MARK: Phase intensity (MVP5-153)

    @Test("a phase-intensity step becomes the zone positions of the phase pace, with that pace as its companion")
    func phaseIntensityStep() throws {
        // 240 / 0.9 = 266.7 s/km, in zone 3 (249.6 to 270.4 s/km) for the fixture athlete.
        let result = resolve([step(target: .phaseIntensity)], fraction: 0.9)
        let resolved = result.workout.blocks[0].steps[0]
        let phasePace = 240 / 0.9
        guard case .pace(let pace)? = resolved.companionTarget, case .heartRateZoneRange(let positions)? = resolved.target else {
            Issue.record("not resolved: \(String(describing: resolved.target))"); return
        }
        #expect(abs((pace.lowerBound + pace.upperBound) / 2 - phasePace) < 1e-9)
        #expect(abs(pace.upperBound - phasePace * 1.02) < 1e-9)
        // The positions give back the pace band: the lower position is the slow end, the upper the fast end.
        let back = try #require(StepTargetResolver.paceRange(zonePositions: positions, in: athlete.paceModel))
        #expect(abs(back.lowerBound - pace.lowerBound) < 1e-6 && abs(back.upperBound - pace.upperBound) < 1e-6)
        #expect(positions.lowerBound >= 2.9 && positions.upperBound <= 3.6)
        #expect(result.unresolved.isEmpty)
    }

    @Test("the same fraction is another zone for another race: 86 % of a marathon pace is easy, 86 % of a 5k pace is moderate")
    func phaseIntensityFollowsTheRace() {
        func positions(racePace: Double) -> ClosedRange<Double> {
            let result = resolve([step(target: .phaseIntensity)], race: .pace(secondsPerKilometer: racePace), fraction: 0.86)
            guard case .heartRateZoneRange(let range)? = result.workout.blocks[0].steps[0].target else {
                Issue.record("not resolved"); return 0...0
            }
            return range
        }
        let marathon = positions(racePace: 270)   // 86 % is 314 s/km
        let fiveK = positions(racePace: 230)      // 86 % is 267 s/km
        #expect(marathon.upperBound < 2.5)
        #expect(fiveK.lowerBound > 2.9 && fiveK.upperBound < 3.7)
    }

    @Test("a phase-intensity step without a fraction, or without a pace race target, is reported and kept")
    func phaseIntensityProblems() {
        let phase = step(target: .phaseIntensity)
        let noFraction = resolve([phase], fraction: nil)
        #expect(noFraction.unresolved.map(\.reason) == [.noPhaseFraction])
        #expect(noFraction.workout.blocks[0].steps[0].target == .phaseIntensity)
        #expect(resolve([phase], race: nil, fraction: 1).unresolved.map(\.reason) == [.noRaceTarget])
        #expect(resolve([phase], race: .heartRate(beatsPerMinute: 150...160), fraction: 1).unresolved.map(\.reason) == [.unsupportedRaceTarget])
    }

    @Test("a phase pace outside every zone targets the whole nearest edge zone and is reported")
    func phaseIntensityOutsideTheZones() {
        // 240 / 0.4 = 600 s/km, much slower than zone 1; 240 / 2 = 120 s/km, much faster than zone 5.
        let slow = resolve([step(target: .phaseIntensity)], fraction: 0.4)
        #expect(slow.unresolved.map(\.reason) == [.paceOutsideZone(zone: 1, paceZone: nil)])
        #expect(slow.workout.blocks[0].steps[0].target == .heartRateZoneRange(1.0...2.0))
        let fast = resolve([step(target: .phaseIntensity)], fraction: 2)
        #expect(fast.unresolved.map(\.reason) == [.paceOutsideZone(zone: 5, paceZone: nil)])
        #expect(fast.workout.blocks[0].steps[0].target == .heartRateZoneRange(5.0...6.0))
    }

    @Test("without zone settings a phase-intensity step still gets its positions and is reported")
    func phaseIntensityWithoutZones() {
        var bare = athlete
        bare.heartRateZoneHistory = []
        let result = resolve([step(target: .phaseIntensity)], athlete: bare, fraction: 0.9)
        #expect(result.unresolved.map(\.reason) == [.noHeartRateZones])
        guard case .heartRateZoneRange? = result.workout.blocks[0].steps[0].target else { Issue.record("no positions"); return }
    }

    @Test("a phase-intensity step is sent as bpm like any zone target, and its estimate is the same before and after")
    func phaseIntensitySentAsBPM() {
        let planned = resolve([step(target: .phaseIntensity)], fraction: 0.9).workout
        let sent = StepTargetResolver.resolveBPM(planned, on: date, athlete: athlete)
        #expect(sent.unresolved.isEmpty)
        guard case .heartRateRange(let low, let high)? = sent.workout.blocks[0].steps[0].target else { Issue.record("no bpm"); return }
        // Zone 3 is 148 to 162 bpm: the pace band sits around its middle.
        #expect(low > 140 && high < 170 && low < high)
        let estimator = TRIMPPlanEstimator()
        #expect(abs(estimator.estimatedLoad(for: planned, athlete: athlete).value - estimator.estimatedLoad(for: sent.workout, athlete: athlete).value) < 1e-6)
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
            #expect(result.workout.blocks[0].steps[1].target == .heartRateZone(4))
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

    @Test("TRIMP load and duration agree for the zone, the zone positions and the bpm sent to the device")
    func agreesWithEstimatorsForPositions() {
        let model = HeartRateZoneModel(settings: athlete.currentHeartRateZoneSettings!)
        let planned = workout([
            step(target: .heartRateZoneRange(3.0...3.4)), step(target: .heartRateZoneRange(4.2...5.0)), step(target: .heartRateZone(2)),
        ])
        let sent = StepTargetResolver.resolveBPM(planned, on: date, athlete: athlete).workout
        let estimator = TRIMPPlanEstimator()
        #expect(abs(estimator.estimatedLoad(for: planned, athlete: athlete).value - estimator.estimatedLoad(for: sent, athlete: athlete).value) < 1e-6)
        #expect(abs(WorkoutDurationEstimator().duration(for: planned, athlete: athlete) - WorkoutDurationEstimator().duration(for: sent, athlete: athlete)) < 1e-6)
        #expect(model.intensityZone(for: .heartRateZoneRange(3.0...3.4)) == 3 && model.intensityZone(for: .heartRateZoneRange(3.7...4.5)) == 4)
    }

    @Test("the estimates agree before and after the conversion under every zone method, also for positions across a boundary")
    func agreesForEveryZoneMethod() {
        let methods: [HeartRateZoneMethod] = [.karvonen, .percentageOfMaxHeartRate, .lactateThreshold]
        for method in methods {
            let athlete = AthleteProfile.fixture(lactateThresholdHeartRateBPM: 165, zoneMethod: method)
            let planned = workout([step(target: .heartRateZoneRange(2.5...3.5)), step(target: .heartRateZoneRange(1.2...4.9)), step(target: .heartRateZoneRange(4.5...6.0))])
            let sent = StepTargetResolver.resolveBPM(planned, on: date, athlete: athlete)
            #expect(sent.unresolved.isEmpty, "\(method)")
            let estimator = TRIMPPlanEstimator()
            #expect(abs(estimator.estimatedLoad(for: planned, athlete: athlete).value - estimator.estimatedLoad(for: sent.workout, athlete: athlete).value) < 1e-6, "\(method)")
            let zones = HeartRateZoneModel(settings: athlete.currentHeartRateZoneSettings!)
            for (before, after) in zip(planned.blocks[0].steps, sent.workout.blocks[0].steps) {
                #expect(zones.intensityZone(for: before.target) == zones.intensityZone(for: after.target), "\(method)")
            }
        }
    }

    @Test("a threshold-based zone method without a threshold heart rate cannot turn positions into bpm")
    func positionsNeedTheThresholdForThatMethod() {
        let athlete = AthleteProfile.fixture(zoneMethod: .lactateThreshold)
        let result = resolve([step(target: .heartRateZoneRange(3.0...3.4))], athlete: athlete)
        #expect(result.unresolved.map(\.reason) == [.zoneUnavailable(3)])
        #expect(StepTargetResolver.resolveBPM(result.workout, on: date, athlete: athlete).unresolved.map(\.reason) == [.zoneUnavailable(3)])
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
