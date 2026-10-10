import Foundation
import Testing
@testable import TrainingCore

/// Custom templates through the calendar export and import (MVP2-141).
@Suite("CalendarTemplateImport")
struct CalendarTemplateImportTests {
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)

    /// A custom template: a warm-up, a repeat whose count and effort are parameters, a fixed cool-down.
    private func intervals(id: UUID = UUID(), name: String = "My intervals") -> WorkoutTemplate {
        WorkoutTemplate(
            id: id, name: name, titleName: "Mine", sport: .running,
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
                        TemplateStep(kind: .recovery, goal: .distance(.parameter("far"))),
                    ],
                    repetitions: .parameter("reps")
                ),
                TemplateBlock(steps: [TemplateStep(kind: .cooldown, goal: .open)]),
            ]
        )
    }

    private func export(
        _ workouts: [StructuredWorkout], templates: [WorkoutTemplate], planDay: Int = 4
    ) -> CalendarExport {
        let plans = workouts.map { PlannedActivity(workoutID: $0.id, date: day(planDay)) }
        return CalendarExportBuilder().build(
            from: day(0), through: day(6, hour: 12), activities: [], plans: plans, workouts: workouts,
            templates: templates, metrics: [], athlete: athlete, today: day(3, hour: 9), generatedAt: day(3, hour: 9)
        )
    }

    private func roundTripped(_ file: CalendarExport) throws -> CalendarExport {
        try CalendarExport.decode(from: file.jsonData())
    }

    private func plan(
        _ file: CalendarExport, plans: [PlannedActivity] = [], workouts: [StructuredWorkout] = [],
        templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all, canAddTemplates: Bool = true
    ) -> CalendarImportPlan {
        CalendarImportPlanner().plan(
            for: file, existingPlans: plans, existingWorkouts: workouts, existingTemplates: templates,
            canAddTemplates: canAddTemplates, athlete: athlete, today: day(0)
        )
    }

    // MARK: Export

    @Test("a plan built from a custom template exports the template's definition once, and the entry names it with its values")
    func exportsDefinitionOnce() throws {
        let template = intervals()
        let first = try template.instantiate(values: ["reps": 6, "effort": 3])
        let second = try template.instantiate()
        let file = export([first, second], templates: BuiltInWorkoutTemplates.all + [template])

        #expect(file.templates.count == 1)
        #expect(file.templates.first?.id == template.id.uuidString)
        let entries = file.days.flatMap(\.activities)
        #expect(entries.map(\.templateID) == [template.id.uuidString, template.id.uuidString])
        #expect(entries.first?.parameterValues == ["reps": 6, "effort": 3, "far": 400])
    }

    @Test("a built-in template is named by id but its definition isn't repeated")
    func builtInNotRepeated() throws {
        let workout = try BuiltInWorkoutTemplates.baseHillSprints.instantiate()
        let file = export([workout], templates: BuiltInWorkoutTemplates.all)

        #expect(file.templates.isEmpty)
        #expect(file.days.flatMap(\.activities).first?.templateID == BuiltInWorkoutTemplates.baseHillSprints.id.uuidString)
    }

    @Test("an archived template that a plan uses is exported; one no plan uses isn't")
    func archivedExportedOnlyWhenUsed() throws {
        var used = intervals(name: "Used")
        used.archivedDate = day(1)
        let unused = intervals(name: "Unused")
        let file = export([try used.instantiate()], templates: [used, unused])

        #expect(file.templates.map(\.name) == ["Used"])
    }

    @Test("a workout that isn't from a template exports no template id or values")
    func plainWorkoutHasNoTemplate() {
        let workout = StructuredWorkout(
            name: "Plain", sport: .running, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600))])]
        )
        let entry = export([workout], templates: []).days.flatMap(\.activities).first

        #expect(entry?.templateID == nil)
        #expect(entry?.parameterValues == nil)
    }

    @Test("the definition survives the JSON round trip and reads back as the same template")
    func definitionRoundTrips() throws {
        let template = intervals()
        let file = try roundTripped(export([try template.instantiate()], templates: [template]))

        let read = try #require(file.templates.first?.workoutTemplate())
        #expect(read == template)
    }

    @Test("a file written before templates were exported still reads, with no templates")
    func oldFileReads() throws {
        let data = try export([try intervals().instantiate()], templates: []).jsonData()
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["templates"] = nil
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let file = try CalendarExport.decode(from: stripped)

        #expect(file.templates.isEmpty)
    }

    // MARK: Import

    @Test("importing adds the template and rebuilds the workout from it, with its parameter values")
    func importAddsTemplateAndLinks() throws {
        let template = intervals()
        let workout = try template.instantiate(values: ["reps": 6, "effort": 3])
        let file = try roundTripped(export([workout], templates: [template]))

        let result = plan(file)

        #expect(result.templates == [template])
        let rebuilt = try #require(result.workouts.first)
        #expect(rebuilt.templateID == template.id)
        #expect(rebuilt.parameterValues == workout.parameterValues)
        #expect(rebuilt.blocks == workout.blocks)
        #expect(result.report.templatesAdded == 1)
        #expect(result.report.added == 1)
    }

    @Test("an equal template already in the library is linked to, whatever its name or id")
    func equalTemplateLinked() throws {
        let theirs = intervals(name: "Theirs")
        let mine = intervals(name: "Mine")  // a different id and name, the same definition
        let file = try roundTripped(export([try theirs.instantiate()], templates: [theirs]))

        let result = plan(file, templates: BuiltInWorkoutTemplates.all + [mine])

        #expect(result.templates.isEmpty)
        #expect(result.workouts.first?.templateID == mine.id)
        #expect(result.report.templatesLinked == 1)
        #expect(result.report.templatesAdded == 0)
    }

    @Test("a template whose id is taken by a different definition is added as a copy with a new id")
    func sameIDDifferentDefinitionCopied() throws {
        let theirs = intervals()
        var mine = theirs
        mine.blocks.removeLast()  // the same id, a different definition
        let file = try roundTripped(export([try theirs.instantiate()], templates: [theirs]))

        let result = plan(file, templates: BuiltInWorkoutTemplates.all + [mine])

        let added = try #require(result.templates.first)
        #expect(added.id != theirs.id)
        #expect(added.blocks == theirs.blocks)
        #expect(result.workouts.first?.templateID == added.id)
        #expect(result.report.templatesCopied == 1)
        #expect(result.report.templatesAdded == 0)
    }

    @Test("a template only used by plans that aren't added isn't added either")
    func unusedTemplateNotAdded() throws {
        let template = intervals()
        let workout = try template.instantiate()
        let stored = PlannedActivity(workoutID: workout.id, date: day(4))
        let file = try roundTripped(export([workout], templates: [template]))

        let result = plan(file, plans: [stored], workouts: [workout], templates: BuiltInWorkoutTemplates.all + [template])

        #expect(result.plans.isEmpty)
        #expect(result.templates.isEmpty)
        #expect(result.report.templatesLinked == 0)
        #expect(result.report.skippedDuplicates == 1)
    }

    @Test("two file templates with equal definitions become one template")
    func equalFileTemplatesMerge() throws {
        let one = intervals(name: "One")
        let two = intervals(name: "Two")
        let file = try roundTripped(export(
            [try one.instantiate(), try two.instantiate(values: ["reps": 5])], templates: [one, two]
        ))

        let result = plan(file)

        #expect(result.templates.count == 1)
        #expect(Set(result.workouts.compactMap(\.templateID)) == [result.templates[0].id])
    }

    @Test("a built-in template an entry names links the workout to it without a definition in the file")
    func builtInLinked() throws {
        let workout = try BuiltInWorkoutTemplates.baseHillSprints.instantiate(values: ["reps": 5, "rest": 180])
        let file = try roundTripped(export([workout], templates: BuiltInWorkoutTemplates.all))

        let result = plan(file)

        #expect(result.templates.isEmpty)
        #expect(result.workouts.first?.templateID == BuiltInWorkoutTemplates.baseHillSprints.id)
        #expect(result.workouts.first?.parameterValues?["reps"] == 5)
    }

    @Test("a template the library lacks and the file doesn't define falls back to the steps, without a link")
    func unknownTemplateFallsBackToSteps() throws {
        let template = intervals()
        let workout = try template.instantiate()
        var file = try roundTripped(export([workout], templates: [template]))
        file = CalendarExport(
            schemaVersion: file.schemaVersion, generatedAt: file.generatedAt, timeZone: file.timeZone,
            firstDay: file.firstDay, lastDay: file.lastDay, days: file.days, templates: []
        )

        let result = plan(file)

        let rebuilt = try #require(result.workouts.first)
        #expect(rebuilt.templateID == nil)
        #expect(rebuilt.blocks == workout.blocks)
        #expect(result.report.added == 1)
    }

    @Test("a definition that can't be read is counted, and its workouts are rebuilt from their steps")
    func unreadableDefinitionRejected() throws {
        let template = intervals()
        let workout = try template.instantiate()
        let file = try roundTripped(export([workout], templates: [template]))
        // A step that refers to a parameter the template doesn't declare.
        let json = try #require(String(data: file.jsonData(), encoding: .utf8))
        let broken = try CalendarExport.decode(from: Data(json.replacingOccurrences(of: "\"durationParameter\" : \"effort\"", with: "\"durationParameter\" : \"missing\"").utf8))

        let result = plan(broken)

        #expect(result.templates.isEmpty)
        #expect(result.report.templatesRejected == 1)
        #expect(result.workouts.first?.templateID == nil)
        #expect(result.report.added == 1)
    }

    @Test("without a template store, a new template isn't added and its workout is rebuilt from its steps")
    func noTemplateStore() throws {
        let template = intervals()
        let file = try roundTripped(export([try template.instantiate()], templates: [template]))

        let result = plan(file, canAddTemplates: false)

        #expect(result.templates.isEmpty)
        #expect(result.workouts.first?.templateID == nil)
        #expect(result.report.templatesRejected == 1)
    }

    @Test("a stored plan counts as a duplicate even when its workout has a template link and the file's doesn't")
    func duplicateIgnoresTemplateLink() throws {
        let template = intervals()
        let linked = try template.instantiate()
        let stored = PlannedActivity(workoutID: linked.id, date: day(4))
        // The same workout in a file written without template information.
        let plain = StructuredWorkout(name: linked.name, sport: linked.sport, blocks: linked.blocks)
        let file = try roundTripped(export([plain], templates: []))

        let result = plan(file, plans: [stored], workouts: [linked])

        #expect(result.plans.isEmpty)
        #expect(result.report.skippedDuplicates == 1)
    }

    @Test("a file entry with a template link doesn't reuse an equal stored workout that has none")
    func linkedEntryGetsLinkedWorkout() throws {
        let template = intervals()
        let linked = try template.instantiate()
        let plain = StructuredWorkout(name: linked.name, sport: linked.sport, blocks: linked.blocks)
        let file = try roundTripped(export([linked], templates: [template], planDay: 5))

        let result = plan(file, workouts: [plain])

        #expect(result.workouts.count == 1)
        #expect(result.workouts.first?.templateID == template.id)
        #expect(result.plans.first?.workoutID == result.workouts.first?.id)
    }
}

@MainActor
@Suite("CalendarTemplateImport model", .serialized)
struct CalendarTemplateImportModelTests {
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)))
    }

    @Test("importing stores the template, then the workout linked to it, then the plan; a second import adds nothing")
    func importStoresTemplateWorkoutAndPlan() async throws {
        let template = WorkoutTemplate(
            name: "Custom", sport: .running,
            parameters: [WorkoutTemplateParameter(key: "minutes", name: "Minutes", unit: .minutes, defaultValue: 30)],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("minutes")))])]
        )
        let workout = try template.instantiate(values: ["minutes": 45])
        let file = CalendarExportBuilder().build(
            from: day(0), through: day(6), activities: [], plans: [PlannedActivity(workoutID: workout.id, date: day(4))],
            workouts: [workout], templates: [template], metrics: [], athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190),
            today: day(0), generatedAt: day(0)
        )
        let (_, model) = makeModel()

        let report = try await model.importCalendar(file, asOf: day(0))

        #expect(report.added == 1)
        #expect(report.templatesAdded == 1)
        #expect(model.templates.map(\.id) == [template.id])
        let imported = try #require(model.workouts.first)
        #expect(imported.templateID == template.id)
        #expect(imported.parameterValues == ["minutes": 45])

        let second = try await model.importCalendar(file, asOf: day(0))
        #expect(second.added == 0)
        #expect(model.templates.count == 1)
        #expect(model.workouts.count == 1)
    }
}
