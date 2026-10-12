import Foundation
import Testing
@testable import TrainingCore

/// The steps the Watch records for a plan-started workout, and laying them over the plan (MVP2-146).
@Suite("ActivityStep")
struct ActivityStepTests {
    private let base = Date(timeIntervalSince1970: 1_699_920_000)

    private func step(
        _ keyPath: String, from start: Double, seconds: Double, distance: Double? = nil, heartRate: Double? = nil
    ) -> ActivityStep {
        let parts = ActivityStep.components(ofKeyPath: keyPath)!
        return ActivityStep(
            block: parts.block, repetition: parts.repetition, step: parts.step,
            start: base.addingTimeInterval(start), end: base.addingTimeInterval(start + seconds),
            distanceMeters: distance, averageHeartRateBPM: heartRate
        )
    }

    // MARK: Key paths and figures

    @Test("a key path is three non-negative integers; anything else isn't one")
    func keyPathParsing() {
        let parsed = ActivityStep.components(ofKeyPath: "2.3.1")
        #expect(parsed?.block == 2 && parsed?.repetition == 3 && parsed?.step == 1)
        #expect(ActivityStep.components(ofKeyPath: "0.0.0")?.block == 0)
        for bad in ["", "1.2", "1.2.3.4", "a.b.c", "1..2", "-1.0.0", "1.0.x"] {
            #expect(ActivityStep.components(ofKeyPath: bad) == nil, "\(bad)")
        }
    }

    @Test("pace is duration over distance, per kilometer; without a usable distance there is none")
    func pace() {
        // The long run's 10 km step: 65:22 for 9993.82 m is 6:32 per kilometer.
        let main = ActivityStep(
            block: 1, repetition: 0, step: 0, start: base, end: base.addingTimeInterval(3922), distanceMeters: 9993.82
        )
        #expect(abs((main.averagePaceSecondsPerKilometer ?? 0) - 392.4) < 0.5)
        #expect(step("0.0.0", from: 0, seconds: 300).averagePaceSecondsPerKilometer == nil)
        #expect(step("0.0.0", from: 0, seconds: 300, distance: 0.4).averagePaceSecondsPerKilometer == nil)
    }

    @Test("a step's duration defaults to its end minus its start, and can be shorter when there was a pause")
    func durationDefault() {
        #expect(step("0.0.0", from: 0, seconds: 300).duration == 300)
        let paused = ActivityStep(block: 0, repetition: 0, step: 0, start: base, end: base.addingTimeInterval(300), duration: 270)
        #expect(paused.duration == 270)
    }

    // MARK: Storage

    @Test("steps survive the activity's JSON round trip, and an activity saved before steps existed still decodes, with none")
    func codableAndLegacy() throws {
        let activity = Activity(
            source: .manual, sport: .running, start: base, duration: 600,
            steps: [step("0.0.0", from: 0, seconds: 300, distance: 800, heartRate: 113)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(activity)
        #expect(try decoder.decode(Activity.self, from: data) == activity)

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["steps"] = nil
        let legacy = try decoder.decode(Activity.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.steps.isEmpty)
        #expect(legacy.id == activity.id)
    }

    // MARK: Aligning with the plan

    /// The hill-sprint workout of the spike: warm-up, run to the hill, 5 × (sprint, recovery), run back,
    /// cool-down. Fourteen steps.
    private func hillSprints(withWarmup: Bool = true) -> StructuredWorkout {
        var blocks: [WorkoutBlock] = []
        if withWarmup { blocks.append(WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(300))])) }
        blocks += [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open)]),
            WorkoutBlock(
                steps: [WorkoutStep(kind: .work, goal: .time(8)), WorkoutStep(kind: .recovery, goal: .time(300))], repetitions: 5
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open)]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300))]),
        ]
        return StructuredWorkout(name: "Hill sprints", sport: .running, blocks: blocks)
    }

    /// The Watch's steps for the hill-sprint workout, key paths as the spike saw them.
    private func hillSprintSteps() -> [ActivityStep] {
        var keyPaths = ["0.0.0", "1.0.0"]
        for repetition in 0..<5 { keyPaths += ["2.\(repetition).0", "2.\(repetition).1"] }
        keyPaths += ["3.0.0", "4.0.0"]
        var clock = 0.0
        return keyPaths.map { keyPath in
            let parts = ActivityStep.components(ofKeyPath: keyPath)!
            defer { clock += 60 }
            return ActivityStep(
                block: parts.block, repetition: parts.repetition, step: parts.step,
                start: base.addingTimeInterval(clock), end: base.addingTimeInterval(clock + 60)
            )
        }
    }

    @Test("the hill-sprint workout's fourteen recorded steps line up with its fourteen planned steps, in order")
    func hillSprintsAlign() throws {
        let aligned = try #require(ActivityStepAligner.align(hillSprintSteps(), with: hillSprints()))

        #expect(aligned.count == 14)
        #expect(aligned.allSatisfy { $0 != nil })
        // Planned step 6 is the third sprint: block 2, repetition 2, step 0.
        let third = try #require(aligned[6])
        #expect(third.block == 2 && third.repetition == 2 && third.step == 0)
        #expect(aligned.last??.block == 4)  // the cool-down
    }

    @Test("a planned step the athlete skipped has no recorded step; the others still line up")
    func skippedStep() throws {
        var steps = hillSprintSteps()
        steps.removeAll { $0.block == 2 && $0.repetition == 3 && $0.step == 0 }  // the fourth sprint

        let aligned = try #require(ActivityStepAligner.align(steps, with: hillSprints()))

        #expect(aligned.count == 14)
        #expect(aligned[8] == nil)
        #expect(aligned.compactMap { $0 }.count == 13)
    }

    @Test("without a warm-up block, either numbering of the Watch's blocks is accepted")
    func noWarmupBothNumberings() throws {
        let workout = hillSprints(withWarmup: false)
        // Numbered from 0 (the workout's own block index): no warm-up step, blocks start at 0.
        let fromZero = hillSprintSteps().dropFirst().map { step in
            ActivityStep(
                block: step.block - 1, repetition: step.repetition, step: step.step, start: step.start, end: step.end
            )
        }
        // Numbered from 1: the warm-up's slot kept, so the blocks keep their numbers.
        let fromOne = Array(hillSprintSteps().dropFirst())

        for steps in [Array(fromZero), fromOne] {
            let aligned = try #require(ActivityStepAligner.align(steps, with: workout))
            #expect(aligned.count == 13)
            #expect(aligned.allSatisfy { $0 != nil })
        }
    }

    @Test("a partial recording that fits either numbering of a workout with no warm-up is not aligned, so no step lands on the wrong planned one")
    func partialRecordingIsAmbiguous() throws {
        // A, then B three times; the athlete stopped after A. Numbered from 1 its key is 1.0.0, which in
        // the other numbering is B's first repetition.
        let workout = StructuredWorkout(name: "A then B", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(60))], repetitions: 3),
        ])
        let onlyA = [step("1.0.0", from: 0, seconds: 600)]
        #expect(ActivityStepAligner.align(onlyA, with: workout) == nil)

        // The same recording with a second step is unambiguous: from 1 the second step is 2.0.0.
        let aAndB = [step("1.0.0", from: 0, seconds: 600), step("2.0.0", from: 600, seconds: 60)]
        let aligned = try #require(ActivityStepAligner.align(aAndB, with: workout))
        #expect(aligned.count == 4)
        #expect(aligned[0] == aAndB[0] && aligned[1] == aAndB[1])
    }

    @Test("an edited plan that no longer fits the recording gives no alignment")
    func editedPlanDoesNotAlign() {
        // The plan now repeats the sprints three times, but five were recorded.
        var workout = hillSprints()
        workout.blocks[2] = WorkoutBlock(steps: workout.blocks[2].steps, repetitions: 3)

        #expect(ActivityStepAligner.align(hillSprintSteps(), with: workout) == nil)
    }

    @Test("steps whose key paths don't fit are paired in order when there is one for every planned step")
    func orderFallback() throws {
        let odd = hillSprintSteps().enumerated().map { index, step in
            ActivityStep(block: 90 + index, repetition: 0, step: 0, start: step.start, end: step.end)
        }

        let aligned = try #require(ActivityStepAligner.align(odd, with: hillSprints()))

        #expect(aligned.count == 14)
        #expect(aligned.compactMap { $0 } == odd)
    }

    @Test("no recorded steps, or a workout with no steps, gives no alignment")
    func nothingToAlign() {
        #expect(ActivityStepAligner.align([], with: hillSprints()) == nil)
        let empty = StructuredWorkout(name: "Empty", sport: .running, blocks: [])
        #expect(ActivityStepAligner.align(hillSprintSteps(), with: empty) == nil)
    }
}
