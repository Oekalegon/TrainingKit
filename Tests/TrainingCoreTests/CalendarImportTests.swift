import Foundation
import Testing
@testable import TrainingCore

@Suite("CalendarImport")
struct CalendarImportTests {
    /// 2023-11-14 00:00 UTC, so `day(n)` is midnight UTC n days later.
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)

    private func hillSprints() throws -> StructuredWorkout {
        try BuiltInWorkoutTemplates.baseHillSprints.instantiate(values: ["reps": 4, "rest": 240])
    }

    private func export(
        plans: [PlannedActivity] = [], workouts: [StructuredWorkout] = [], activities: [Activity] = []
    ) -> CalendarExport {
        CalendarExportBuilder().build(
            from: day(0), through: day(6, hour: 12), activities: activities, plans: plans, workouts: workouts,
            templates: BuiltInWorkoutTemplates.all, metrics: [], athlete: athlete, today: day(3, hour: 9), generatedAt: day(3, hour: 9)
        )
    }

    private func plan(_ export: CalendarExport, plans: [PlannedActivity] = [], workouts: [StructuredWorkout] = []) -> CalendarImportPlan {
        CalendarImportPlanner().plan(for: export, existingPlans: plans, existingWorkouts: workouts, athlete: athlete)
    }

    @Test("a planned workout round-trips through the export: its blocks, repetitions, goals and targets are rebuilt")
    func roundTrip() throws {
        let workout = try hillSprints()
        let file = export(plans: [PlannedActivity(workoutID: workout.id, date: day(4))], workouts: [workout])

        let result = plan(try CalendarExport.decode(from: file.jsonData()))

        let rebuilt = try #require(result.workouts.first)
        #expect(rebuilt.blocks == workout.blocks)
        #expect(rebuilt.name == workout.name)
        #expect(rebuilt.sport == .running)
        #expect(result.plans.map(\.date) == [day(4)])
        #expect(result.plans.first?.workoutID == rebuilt.id)
        #expect(result.report == CalendarImportReport(added: 1, skippedDuplicates: 0, skippedCompleted: 0, rejected: []))
    }

    @Test("completed activities are skipped and counted; daily metrics aren't imported")
    func completedSkipped() throws {
        let start = day(1, hour: 7)
        let samples = (0..<360).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 150) }
        let ran = Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 1800, distanceMeters: 6000, heartRate: samples)

        let result = plan(export(activities: [ran]))

        #expect(result.plans.isEmpty)
        #expect(result.workouts.isEmpty)
        #expect(result.report.skippedCompleted == 1)
    }

    @Test("importing a file whose plans are already stored adds nothing, and reuses the stored workout")
    func duplicatesSkipped() throws {
        let workout = try hillSprints()
        let stored = PlannedActivity(workoutID: workout.id, date: day(4))
        let file = export(plans: [stored], workouts: [workout])

        let result = plan(file, plans: [stored], workouts: [workout])

        #expect(result.plans.isEmpty)
        #expect(result.workouts.isEmpty)
        #expect(result.report.skippedDuplicates == 1)
        #expect(result.report.added == 0)
    }

    @Test("two identical plans on one day import as two; one already stored leaves one to add")
    func sameDayTwiceCountsOccurrences() throws {
        let workout = try hillSprints()
        let first = PlannedActivity(workoutID: workout.id, date: day(4))
        let second = PlannedActivity(workoutID: workout.id, date: day(4))
        let file = export(plans: [first, second], workouts: [workout])

        #expect(plan(file).plans.count == 2)
        #expect(plan(file).workouts.count == 1)

        let afterOne = plan(file, plans: [first], workouts: [workout])
        #expect(afterOne.plans.count == 1)
        #expect(afterOne.workouts.isEmpty)
        #expect(afterOne.report.skippedDuplicates == 1)
    }

    @Test("an existing equal workout is reused for a plan on a new day")
    func equalWorkoutReused() throws {
        let workout = try hillSprints()
        let file = export(plans: [PlannedActivity(workoutID: workout.id, date: day(5))], workouts: [workout])

        let result = plan(file, plans: [PlannedActivity(workoutID: workout.id, date: day(4))], workouts: [workout])

        #expect(result.workouts.isEmpty)
        #expect(result.plans.first?.workoutID == workout.id)
    }

    @Test("an override survives; an untouched estimate is recomputed; an edited estimate becomes an override")
    func loadOverrides() throws {
        let workout = try hillSprints()
        let overridden = PlannedActivity(workoutID: workout.id, date: day(4), expectedLoadOverride: 77)
        let estimated = PlannedActivity(workoutID: workout.id, date: day(5))
        let file = export(plans: [overridden, estimated], workouts: [workout])

        let untouched = plan(file)
        #expect(untouched.plans.map(\.expectedLoadOverride) == [77, nil])

        // The same file with the second entry's TRIMP edited outside the app.
        var edited = try #require(String(data: file.jsonData(), encoding: .utf8))
        let estimate = try #require(file.days[5].activities.first?.trimp)
        let range = try #require(edited.range(of: "\"trimp\" : \(estimate)"))
        edited.replaceSubrange(range, with: "\"trimp\" : \(estimate + 25)")
        let result = plan(try CalendarExport.decode(from: Data(edited.utf8)))
        #expect(result.plans[1].expectedLoadOverride == estimate + 25)
    }

    @Test("a planned entry on an invalid day is rejected with that reason, and the rest import")
    func invalidDateRejected() throws {
        let workout = try hillSprints()
        let file = export(
            plans: [PlannedActivity(workoutID: workout.id, date: day(4)), PlannedActivity(workoutID: workout.id, date: day(5))],
            workouts: [workout]
        )
        // 2023-11-18 is `day(4)`.
        let json = try #require(String(data: file.jsonData(), encoding: .utf8))
            .replacingOccurrences(of: "\"date\" : \"2023-11-18\"", with: "\"date\" : \"2023-13-45\"")

        let result = plan(try CalendarExport.decode(from: Data(json.utf8)))

        #expect(result.report.added == 1)
        #expect(result.report.rejected.map(\.reason) == [.invalidDate])
        #expect(result.report.rejected.first?.date == "2023-13-45")
    }

    @Test("an entry with a step kind this version doesn't know is rejected as invalid")
    func unknownStepKindRejected() throws {
        let workout = try hillSprints()
        let file = export(plans: [PlannedActivity(workoutID: workout.id, date: day(4))], workouts: [workout])
        let json = try #require(String(data: file.jsonData(), encoding: .utf8))
            .replacingOccurrences(of: "\"kind\" : \"warmup\"", with: "\"kind\" : \"sprint\"")

        let result = plan(try CalendarExport.decode(from: Data(json.utf8)))

        #expect(result.plans.isEmpty)
        #expect(result.report.rejected.map(\.reason) == [.invalidStep])
    }

    @Test("a file written before steps existed has no steps, so its planned entries are rejected as such")
    func oldFileWithoutSteps() throws {
        let workout = try hillSprints()
        let file = export(plans: [PlannedActivity(workoutID: workout.id, date: day(4))], workouts: [workout])
        let json = try #require(String(data: file.jsonData(), encoding: .utf8))
        // Drop every "steps" array, as a pre-MVP2-102 export lacks the key altogether.
        let stripped = json.replacingOccurrences(
            of: "\"steps\"\\s*:\\s*\\[(?:[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]\\s*,?", with: "", options: .regularExpression
        )
        let decoded = try CalendarExport.decode(from: Data(stripped.utf8))

        let result = plan(decoded)

        #expect(result.plans.isEmpty)
        #expect(result.report.rejected.map(\.reason) == [.noSteps])
    }

    @Test("a newer schema version and unreadable data are refused")
    func decodeErrors() throws {
        let file = export()
        let newer = try #require(String(data: file.jsonData(), encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2")

        #expect(throws: CalendarImportError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            try CalendarExport.decode(from: Data(newer.utf8))
        }
        #expect(throws: CalendarImportError.unreadable) { try CalendarExport.decode(from: Data("not json".utf8)) }
    }
}

@MainActor
@Suite("TrainingModel.importCalendar", .serialized)
struct TrainingModelCalendarImportTests {
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)))
    }

    private func makeExport() async throws -> CalendarExport {
        let (store, source) = makeModel()
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()
        try await store.upsert([workout])
        try await store.upsert([PlannedActivity(workoutID: workout.id, date: day(4)), PlannedActivity(workoutID: workout.id, date: day(5))])
        return try await source.calendarExport(from: day(0), through: day(6), asOf: day(3, hour: 9))
    }

    @Test("importing adds the plans and their workout, shows them without a reload, and a second import adds nothing")
    func importsOnce() async throws {
        let file = try await makeExport()
        let (store, model) = makeModel()
        try await model.load(in: day(0)...day(2), asOf: day(3, hour: 9))

        let first = try await model.importCalendar(file, asOf: day(3, hour: 9))
        let second = try await model.importCalendar(file, asOf: day(3, hour: 9))

        #expect(first.added == 2)
        #expect(second.added == 0 && second.skippedDuplicates == 2)
        #expect(try await store.plans(in: day(0)...day(6)).count == 2)
        #expect(try await store.workouts().count == 1)
        #expect(model.plans.count == 2, "the loaded range widened to cover the imported days")
    }

    @Test("a preview reports what would happen and changes nothing")
    func previewChangesNothing() async throws {
        let file = try await makeExport()
        let (store, model) = makeModel()

        let report = try await model.calendarImportPreview(file)

        #expect(report.added == 2)
        #expect(try await store.plans(in: day(0)...day(6)).isEmpty)
        #expect(try await store.workouts().isEmpty)
    }
}
