import Foundation
import Testing
import TrainingCore
@testable import TrainingPersistence

/// The calendar import's template path (MVP2-141) against the real `SwiftDataStore` (MVP2-148): its
/// `WorkoutTemplateStore` and workout and plan stores are the CloudKit-backed ones, so this shows
/// that a template survives the record round trip and that the import's save order and idempotence
/// hold there as they do on `InMemoryStore` (`CalendarTemplateImportTests`).
@MainActor
@Suite("Calendar template import + SwiftData", .serialized)
struct SwiftDataTemplateImportTests {
    /// 2023-11-14 00:00 UTC, so `day(n)` is midnight UTC n days later.
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400)
    }

    private func makeSwiftDataModel() throws -> (SwiftDataStore, TrainingModel) {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
            raceStore: store, athleteStore: store, templateStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: .fixture()))
    }

    /// A custom template using every kind of reference and target the file format can carry.
    private func template(id: UUID = UUID()) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id, name: "Custom intervals", titleName: "Custom", sport: .running,
            parameters: [
                WorkoutTemplateParameter(key: "reps", name: "Reps", unit: .count, defaultValue: 4, range: 2...8),
                WorkoutTemplateParameter(key: "effort", name: "Effort", unit: .minutes, defaultValue: 2, range: 1...5),
                WorkoutTemplateParameter(key: "far", name: "Far", unit: .meters, defaultValue: 400),
            ],
            blocks: [
                TemplateBlock(steps: [TemplateStep(kind: .warmup, goal: .time(.fixed(600)), target: .heartRateZone(2))]),
                TemplateBlock(
                    steps: [
                        TemplateStep(kind: .work, goal: .time(.parameter("effort")), target: .heartRateRange(150, 170)),
                        TemplateStep(kind: .recovery, goal: .distance(.parameter("far")), target: .rpe(3)),
                    ],
                    repetitions: .parameter("reps")
                ),
                TemplateBlock(steps: [TemplateStep(kind: .cooldown, goal: .open)]),
            ]
        )
    }

    /// An export of one plan built from `template` at non-default values, from an in-memory model.
    private func export(using template: WorkoutTemplate) async throws -> CalendarExport {
        let store = InMemoryStore()
        let source = TrainingModel(
            stores: StoreSet(
                activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
                raceStore: store, athleteStore: store, templateStore: store
            ),
            athlete: .fixture()
        )
        try await source.add(template)
        let workout = try template.instantiate(values: ["reps": 6, "effort": 3])
        try await source.add(workout, asOf: day(0))
        try await source.add(PlannedActivity(workoutID: workout.id, date: day(4)), asOf: day(0))
        return try await CalendarExport.decode(
            from: source.calendarExport(from: day(0), through: day(6), asOf: day(0)).jsonData()
        )
    }

    @Test("the template, its linked workout and the plan are stored, and the template reads back as it was")
    func importStoresLinkedRecords() async throws {
        let original = template()
        let file = try await export(using: original)
        let (store, model) = try makeSwiftDataModel()

        let report = try await model.importCalendar(file, asOf: day(0))

        #expect(report.added == 1)
        #expect(report.templatesAdded == 1)
        // Read back from the store, not the model: the records, not the loaded copies.
        let storedTemplates = try await store.templates()
        #expect(storedTemplates == [original])
        let storedWorkout = try #require(try await store.workouts().first)
        #expect(storedWorkout.templateID == original.id)
        #expect(storedWorkout.parameterValues == ["reps": 6, "effort": 3, "far": 400])
        #expect(storedWorkout.blocks[1].repetitions == 6)
        let storedPlan = try #require(try await store.plans(in: day(0)...day(6)).first)
        #expect(storedPlan.workoutID == storedWorkout.id)
    }

    @Test("a second import of the same file adds nothing to any store")
    func secondImportAddsNothing() async throws {
        let file = try await export(using: template())
        let (store, model) = try makeSwiftDataModel()
        try await model.importCalendar(file, asOf: day(0))

        let second = try await model.importCalendar(file, asOf: day(0))

        #expect(second.added == 0)
        #expect(second.skippedDuplicates == 1)
        #expect(try await store.templates().count == 1)
        #expect(try await store.workouts().count == 1)
        #expect(try await store.plans(in: day(0)...day(6)).count == 1)
    }

    @Test("a different template with the same id is added as a copy: both are stored, the old one unchanged")
    func sameIDDifferentDefinitionStoredAsCopy() async throws {
        let theirs = template()
        var mine = theirs
        mine.blocks.removeLast()
        let file = try await export(using: theirs)
        let (store, model) = try makeSwiftDataModel()
        try await model.add(mine)

        let report = try await model.importCalendar(file, asOf: day(0))

        #expect(report.templatesCopied == 1)
        let stored = try await store.templates()
        #expect(stored.count == 2)
        #expect(stored.first { $0.id == theirs.id } == mine)
        let copy = try #require(stored.first { $0.id != theirs.id })
        #expect(copy.blocks == theirs.blocks)
        #expect(try await store.workouts().first?.templateID == copy.id)
    }

    @Test("an equal template already stored is linked to, and no template is added")
    func equalStoredTemplateLinked() async throws {
        let theirs = template()
        var mine = template(id: UUID())  // another id, the same definition
        mine.name = "Mine"
        let file = try await export(using: theirs)
        let (store, model) = try makeSwiftDataModel()
        try await model.add(mine)

        let report = try await model.importCalendar(file, asOf: day(0))

        #expect(report.templatesLinked == 1)
        #expect(report.templatesAdded == 0)
        #expect(try await store.templates().count == 1)
        #expect(try await store.workouts().first?.templateID == mine.id)
    }
}
