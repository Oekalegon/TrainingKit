import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel field tests", .serialized)
struct FieldTestModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel(athlete: AthleteProfile = .fixture(maxHeartRateBPM: 178)) -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    /// Holds `peak` for two minutes after a ramp at a real heart's pace.
    private func testActivity(on start: Date, peak: Double, linkedTo planID: UUID?) -> Activity {
        let ramp: [Double] = stride(from: 150.0, to: peak, by: 10).dropFirst().map { $0 }
        let bpms: [Double] = Array(repeating: 150.0, count: 48) + ramp + Array(repeating: peak, count: 24)
            + ramp.reversed() + Array(repeating: 150.0, count: 48)
        var samples: [HeartRateSample] = []
        for (index, bpm) in bpms.enumerated() {
            samples.append(HeartRateSample(time: start.addingTimeInterval(Double(index) * 5), bpm: bpm))
        }
        return Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: 600,
            heartRate: samples, linkedPlanID: planID
        )
    }

    private func planned(_ model: TrainingModel, template: WorkoutTemplate, on date: Date) async throws -> PlannedActivity {
        let workout = try template.instantiate()
        let plan = PlannedActivity(workoutID: workout.id, date: date)
        try await model.add(workout)
        try await model.add(plan)
        return plan
    }

    /// An activity on `date` linked to a plan of `template`, in the store, for applying a result to.
    private func linkedActivity(
        _ store: InMemoryStore, _ model: TrainingModel, template: WorkoutTemplate, on date: Date
    ) async throws -> Activity {
        let plan = try await planned(model, template: template, on: date)
        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: date, duration: 600, linkedPlanID: plan.id
        )
        try await store.upsert([activity])
        return activity
    }

    // MARK: Reading the result

    @Test("a linked max HR test activity gives a result, read from the store")
    func resultForLinkedTest() async throws {
        let (store, model) = makeModel()
        let plan = try await planned(model, template: BuiltInWorkoutTemplates.maxHRTest, on: day(2))
        let activity = testActivity(on: day(2), peak: 184, linkedTo: plan.id)
        try await store.upsert([activity])

        let result = try await model.fieldTestResult(forActivity: activity.id)

        #expect(result?.measurement == .maxHeartRate)
        #expect(result?.valueBPM == 184)
        #expect(result?.currentBPM == 178)
    }

    @Test("no result for a missing activity, an unlinked one, or one linked to an ordinary workout")
    func noResultWhenNotATest() async throws {
        let (store, model) = makeModel()
        let ordinary = try await planned(model, template: BuiltInWorkoutTemplates.easyRun, on: day(2))
        let unlinked = testActivity(on: day(2), peak: 184, linkedTo: nil)
        let linkedToOrdinary = testActivity(on: day(2), peak: 184, linkedTo: ordinary.id)
        try await store.upsert([unlinked, linkedToOrdinary])

        #expect(try await model.fieldTestResult(forActivity: UUID()) == nil)
        #expect(try await model.fieldTestResult(forActivity: unlinked.id) == nil)
        #expect(try await model.fieldTestResult(forActivity: linkedToOrdinary.id) == nil)
    }

    @Test("a test activity that can't be measured throws why")
    func unmeasurableTestThrows() async throws {
        let (store, model) = makeModel()
        let plan = try await planned(model, template: BuiltInWorkoutTemplates.maxHRTest, on: day(2))
        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(2), duration: 600, linkedPlanID: plan.id
        )
        try await store.upsert([activity])

        await #expect(throws: FieldTestError.noHeartRate) { try await model.fieldTestResult(forActivity: activity.id) }
    }

    @Test("a linked LTHR test activity gives a result through the store, using the recorded steps")
    func lthrResultForLinkedTest() async throws {
        let (store, model) = makeModel()
        let plan = try await planned(model, template: BuiltInWorkoutTemplates.lthrTest, on: day(2))
        let begin = day(2)
        var samples: [HeartRateSample] = []
        var second = 0.0
        while second <= 3000 {
            let bpm: Double = second >= 900 && second < 2700 ? 168 : 140
            samples.append(HeartRateSample(time: begin.addingTimeInterval(second), bpm: bpm))
            second += 5
        }
        let bounds: [(Double, Double)] = [(0, 600), (600, 900), (900, 2700), (2700, 3000)]
        var steps: [ActivityStep] = []
        for (block, bound) in bounds.enumerated() {
            steps.append(ActivityStep(
                block: block, repetition: 0, step: 0,
                start: begin.addingTimeInterval(bound.0), end: begin.addingTimeInterval(bound.1)
            ))
        }
        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: begin, duration: 3000,
            heartRate: samples, linkedPlanID: plan.id, steps: steps
        )
        try await store.upsert([activity])

        let result = try await model.fieldTestResult(forActivity: activity.id)

        #expect(result?.measurement == .lactateThresholdHeartRate)
        #expect(result?.valueBPM == 168)
        #expect(result?.isEstimatedFromPlan == false)
    }

    // MARK: Applying

    @Test("a max HR result lowers the max from the test onward, with the field-test source, and earlier days keep theirs")
    func applyLowersMax() async throws {
        let (store, model) = makeModel()
        let activity = try await linkedActivity(store, model, template: BuiltInWorkoutTemplates.maxHRTest, on: day(5))
        let result = FieldTestResult(
            measurement: .maxHeartRate, activityID: activity.id, activityStart: day(5), valueBPM: 170, currentBPM: 178
        )

        try await model.applyFieldTestResult(result, asOf: day(6))

        let before = try #require(model.athlete.heartRateZoneSettings(asOf: day(4)))
        let after = try #require(model.athlete.heartRateZoneSettings(asOf: day(5)))
        #expect(before.maxHeartRateBPM == 178)
        #expect(after.maxHeartRateBPM == 170)
        #expect(after.maxHeartRateSource == .fieldTest(activityID: activity.id))
    }

    @Test("a lactate threshold result is recorded with the field-test source and leaves the max alone")
    func applyLactateThreshold() async throws {
        let (store, model) = makeModel()
        let activity = try await linkedActivity(store, model, template: BuiltInWorkoutTemplates.lthrTest, on: day(5))
        let result = FieldTestResult(
            measurement: .lactateThresholdHeartRate, activityID: activity.id, activityStart: day(5),
            valueBPM: 168, currentBPM: nil
        )

        try await model.applyFieldTestResult(result, asOf: day(6))

        let settings = try #require(model.athlete.heartRateZoneSettings(asOf: day(5)))
        #expect(settings.lactateThresholdHeartRateBPM == 168)
        #expect(settings.lactateThresholdSource == .fieldTest(activityID: activity.id))
        #expect(settings.maxHeartRateBPM == 178)
        #expect(try await store.athleteProfile()?.heartRateZoneSettings(asOf: day(5))?.lactateThresholdHeartRateBPM == 168)
    }

    @Test("later entries that still carry the old value follow, but a later measurement is kept")
    func laterEntries() {
        let workoutPeak = HeartRateZoneSettings(
            effectiveDate: day(20), restingHeartRateBPM: 50, maxHeartRateBPM: 185,
            maxHeartRateSource: .workout(activityID: UUID())
        )
        var athlete = AthleteProfile.fixture(maxHeartRateBPM: 178)
        var carried = athlete.heartRateZoneHistory[0]
        carried.effectiveDate = day(10)
        carried.restingHeartRateBPM = 48
        athlete.heartRateZoneHistory.append(carried)
        athlete.heartRateZoneHistory.append(workoutPeak)
        let id = UUID()

        let updated = athlete.settingMaxHeartRate(to: 170, from: day(5), source: .fieldTest(activityID: id))

        #expect(updated.heartRateZoneSettings(asOf: day(4))?.maxHeartRateBPM == 178)
        #expect(updated.heartRateZoneSettings(asOf: day(5))?.maxHeartRateBPM == 170)
        #expect(updated.heartRateZoneSettings(asOf: day(10))?.maxHeartRateBPM == 170)
        #expect(updated.heartRateZoneSettings(asOf: day(10))?.restingHeartRateBPM == 48)
        #expect(updated.heartRateZoneSettings(asOf: day(20))?.maxHeartRateBPM == 185)
    }

    @Test("a result for an activity that was since deleted, or unlinked from its test, is not applied")
    func staleResultNotApplied() async throws {
        let (store, model) = makeModel()
        let plan = try await planned(model, template: BuiltInWorkoutTemplates.maxHRTest, on: day(5))
        let activity = testActivity(on: day(5), peak: 170, linkedTo: plan.id)
        try await store.upsert([activity])
        let result = try #require(try await model.fieldTestResult(forActivity: activity.id))
        let before = model.athlete

        var unlinked = activity
        unlinked.linkedPlanID = nil
        try await store.upsert([unlinked])
        try await model.applyFieldTestResult(result, asOf: day(6))
        #expect(model.athlete == before)

        // Linked to an LTHR test instead: the wrong kind of test for a max heart rate result.
        let lthrPlan = try await planned(model, template: BuiltInWorkoutTemplates.lthrTest, on: day(5))
        var relinked = activity
        relinked.linkedPlanID = lthrPlan.id
        try await store.upsert([relinked])
        try await model.applyFieldTestResult(result, asOf: day(6))
        #expect(model.athlete == before)

        try await model.applyFieldTestResult(
            FieldTestResult(measurement: .maxHeartRate, activityID: UUID(), activityStart: day(5), valueBPM: 170, currentBPM: 178),
            asOf: day(6)
        )
        #expect(model.athlete == before)
    }

    @Test("applying leaves cached metrics from before the test untouched")
    func applyKeepsEarlierCache() async throws {
        let cache = InMemoryStore()
        let early = FitnessMetrics(
            day: day(-10), load: 0, ctl: 42, atl: 42, tsb: 0,
            monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
        )
        try await cache.upsert([early])
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, fitnessMetricsCacheStore: cache
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(maxHeartRateBPM: 178))
        let plan = try await planned(model, template: BuiltInWorkoutTemplates.maxHRTest, on: day(5))
        let activity = testActivity(on: day(5), peak: 170, linkedTo: plan.id)
        try await store.upsert([activity])
        let result = try #require(try await model.fieldTestResult(forActivity: activity.id))

        try await model.applyFieldTestResult(result, asOf: day(6))

        let kept = try await cache.cachedMetrics(in: day(-10)...day(-10))
        #expect(kept.map(\.ctl) == [42])
    }

    @Test("a lactate threshold result is date-effective: earlier entries keep theirs and later carried ones follow")
    func lactateThresholdLaterEntries() {
        var athlete = AthleteProfile.fixture(lactateThresholdHeartRateBPM: 160)
        var carried = athlete.heartRateZoneHistory[0]
        carried.effectiveDate = day(10)
        athlete.heartRateZoneHistory.append(carried)
        var later = athlete.heartRateZoneHistory[0]
        later.effectiveDate = day(20)
        later.lactateThresholdHeartRateBPM = 175
        later.lactateThresholdSource = .fieldTest(activityID: UUID())
        athlete.heartRateZoneHistory.append(later)

        let updated = athlete.settingLactateThresholdHeartRate(to: 166, from: day(5), source: .fieldTest(activityID: UUID()))

        #expect(updated.heartRateZoneSettings(asOf: day(4))?.lactateThresholdHeartRateBPM == 160)
        #expect(updated.heartRateZoneSettings(asOf: day(5))?.lactateThresholdHeartRateBPM == 166)
        #expect(updated.heartRateZoneSettings(asOf: day(10))?.lactateThresholdHeartRateBPM == 166)
        #expect(updated.heartRateZoneSettings(asOf: day(20))?.lactateThresholdHeartRateBPM == 175)
    }

    @Test("a result dated before every entry applies to the whole history")
    func resultBeforeFirstEntry() {
        var athlete = AthleteProfile.fixture(maxHeartRateBPM: 178)
        athlete.heartRateZoneHistory[0].effectiveDate = day(10)

        let updated = athlete.settingMaxHeartRate(to: 170, from: day(5), source: .fieldTest(activityID: UUID()))

        #expect(updated.heartRateZoneSettings(asOf: day(5))?.maxHeartRateBPM == 170)
        #expect(updated.heartRateZoneSettings(asOf: day(12))?.maxHeartRateBPM == 170)
    }

    @Test("applying the value and source already in effect changes nothing")
    func applyIsIdempotent() async throws {
        let (store, model) = makeModel()
        let activity = try await linkedActivity(store, model, template: BuiltInWorkoutTemplates.maxHRTest, on: day(5))
        let result = FieldTestResult(
            measurement: .maxHeartRate, activityID: activity.id, activityStart: day(5), valueBPM: 170, currentBPM: 178
        )
        try await model.applyFieldTestResult(result, asOf: day(6))
        let once = model.athlete

        try await model.applyFieldTestResult(result, asOf: day(6))

        #expect(model.athlete == once)
    }

    // MARK: Sources

    @Test("the sources round-trip, and settings saved before the LTHR source existed read it as manual")
    func sourcesDecode() throws {
        let id = UUID()
        let settings = HeartRateZoneSettings(
            effectiveDate: day(0), restingHeartRateBPM: 50, maxHeartRateBPM: 178,
            maxHeartRateSource: .fieldTest(activityID: id), lactateThresholdHeartRateBPM: 160,
            lactateThresholdSource: .fieldTest(activityID: id)
        )
        #expect(try JSONDecoder().decode(HeartRateZoneSettings.self, from: JSONEncoder().encode(settings)) == settings)

        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        #expect(json.removeValue(forKey: "lactateThresholdSource") != nil)
        let legacy = try JSONDecoder().decode(HeartRateZoneSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.lactateThresholdSource == .manual)
        #expect(legacy.maxHeartRateSource == .fieldTest(activityID: id))
    }
}
