import Foundation
import Testing
@testable import TrainingCore

/// Importing the completed activities in a calendar file as placeholders, and HealthKit replacing them (MVP2-107).
@MainActor
@Suite("Calendar activity import", .serialized)
struct CalendarActivityImportTests {
    private let start = Date(timeIntervalSince1970: 1_699_920_000 + 86_400 + 7 * 3600)
    private let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
    private let today = Date(timeIntervalSince1970: 1_699_920_000 + 3 * 86_400)

    /// A running activity at `start`, 30 minutes at 150 bpm so the export gives it a TRIMP.
    private func ran(sourceID: UUID?, duration: Double = 1800) -> Activity {
        let samples = (0..<Int(duration / 5)).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 150) }
        return Activity(
            source: sourceID.map { .healthKit($0) } ?? .manual, sport: .running, start: start, duration: duration,
            distanceMeters: 6000, heartRate: samples
        )
    }

    private func file(_ activities: [Activity]) -> CalendarExport {
        CalendarExportBuilder().build(
            from: start.addingTimeInterval(-86_400), through: start.addingTimeInterval(86_400), activities: activities,
            plans: [], workouts: [], templates: [], metrics: [], athlete: athlete, today: today, generatedAt: today
        )
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: ImportAnchor(data: Data([1])))
        }
    }

    @Test("the export carries a HealthKit workout's id as the entry's source id")
    func sourceIDRoundTrip() throws {
        let id = UUID()
        let decoded = try CalendarExport.decode(from: file([ran(sourceID: id)]).jsonData())
        #expect(decoded.days.flatMap(\.activities).first?.sourceID == id.uuidString)
    }

    @Test("the placeholder is stored under the workout's id and scored by its imported load")
    func placeholderStored() async throws {
        let (store, model) = makeModel()
        let id = UUID()
        let report = try await model.importCalendar(file([ran(sourceID: id)]), asOf: today)

        #expect(report.activitiesAdded == 1)
        let stored = try #require(try await store.activity(source: .healthKit(id)))
        #expect(stored.id == id)
        #expect(stored.isCalendarImport)
        let expected = try #require(file([ran(sourceID: id)]).days.flatMap(\.activities).first?.trimp)
        #expect(stored.importedLoad == expected)
        #expect(stored.heartRate.isEmpty)
        let load = try ImportedLoadCalculator().load(for: stored, athlete: athlete)
        #expect(load.value == expected)
    }

    @Test("importing the same file twice adds the activity once")
    func notRepeated() async throws {
        let (store, model) = makeModel()
        let export = file([ran(sourceID: UUID())])
        _ = try await model.importCalendar(export, asOf: today)
        let second = try await model.importCalendar(export, asOf: today)

        #expect(second.activitiesAdded == 0)
        #expect(second.activitiesSkippedDuplicates == 1)
        let all = try await store.activityListItems(in: start.addingTimeInterval(-86_400)...start.addingTimeInterval(86_400))
        #expect(all.count == 1)
    }

    @Test("an entry with no source id is skipped when a workout at the same time is stored")
    func overlapSkipped() async throws {
        let (store, model) = makeModel()
        try await store.upsert([Activity(source: .healthKit(UUID()), sport: .running, start: start.addingTimeInterval(60), duration: 1750)])
        let report = try await model.importCalendar(file([ran(sourceID: nil)]), asOf: today)
        #expect(report.activitiesAdded == 0)
        #expect(report.activitiesSkippedDuplicates == 1)
    }

    @Test("an entry without a duration is rejected")
    func invalidRejected() throws {
        let json = try #require(String(data: file([ran(sourceID: nil)]).jsonData(), encoding: .utf8))
            .replacingOccurrences(of: "\"durationSeconds\" : 1800", with: "\"durationSeconds\" : 0")
        let result = CalendarImportPlanner().plan(
            for: try CalendarExport.decode(from: Data(json.utf8)), existingPlans: [], existingWorkouts: [], athlete: athlete, today: today
        )
        #expect(result.activities.isEmpty)
        #expect(result.report.rejected.first?.reason == .invalidActivity)
    }

    @Test("HealthKit's import of the same workout replaces the placeholder in place")
    func healthKitReplacesBySource() async throws {
        let (store, model) = makeModel()
        let id = UUID()
        _ = try await model.importCalendar(file([ran(sourceID: id)]), asOf: today)
        let real = Activity(
            id: id, source: .healthKit(id), sport: .running, start: start, duration: 1800, distanceMeters: 6000,
            heartRate: [HeartRateSample(time: start, bpm: 150)]
        )
        try await model.importActivities(from: StubImporter(activities: [real]), asOf: today)

        let stored = try #require(try await store.activity(id: id))
        #expect(!stored.isCalendarImport)
        #expect(stored.importedLoad == nil)
        #expect(stored.heartRate.count == 1)
    }

    @Test("HealthKit's import replaces a placeholder with no source id by overlap, and leaves a different workout alone")
    func healthKitReplacesByOverlap() async throws {
        let (store, model) = makeModel()
        _ = try await model.importCalendar(file([ran(sourceID: nil)]), asOf: today)
        let other = Activity(source: .healthKit(UUID()), sport: .cycling, start: start, duration: 1800)
        let real = Activity(source: .healthKit(UUID()), sport: .running, start: start.addingTimeInterval(30), duration: 1790)
        try await model.importActivities(from: StubImporter(activities: [real, other]), asOf: today)

        let all = try await store.activityListItems(in: start.addingTimeInterval(-86_400)...start.addingTimeInterval(86_400))
        #expect(all.count == 2)
        #expect(all.allSatisfy { !$0.isCalendarImport })
    }

    @Test("a calendar import doesn't touch HealthKit's import anchor")
    func anchorUntouched() async throws {
        let (store, model) = makeModel()
        try await model.importActivities(from: StubImporter(activities: []), asOf: today)
        let anchor = try await store.importAnchor()
        _ = try await model.importCalendar(file([ran(sourceID: UUID())]), asOf: today)
        #expect(try await store.importAnchor() == anchor)
    }

    @Test("an activity stored before the new fields existed still decodes")
    func legacyDecode() throws {
        let activity = Activity(source: .manual, sport: .running, start: start, duration: 600)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any])
        json.removeValue(forKey: "importedLoad")
        json.removeValue(forKey: "isCalendarImport")
        let decoded = try JSONDecoder().decode(Activity.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.isCalendarImport == false)
        #expect(decoded.importedLoad == nil)
    }
}
