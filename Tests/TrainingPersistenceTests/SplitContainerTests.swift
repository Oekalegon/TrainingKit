import Foundation
import SwiftData
import Testing
@testable import TrainingPersistence
import TrainingCore

/// MVP2-131: health-derived data stays local, only the athlete's own plans and preferences sync.
@Suite("Split container (MVP2-131)", .serialized)
struct SplitContainerTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SplitContainerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func names(_ types: [any PersistentModel.Type]) -> Set<String> {
        Set(types.map { String(describing: $0) })
    }

    // MARK: The partition

    @Test("every model is in exactly one of the synced and local sets")
    func partition() {
        let synced = names(TrainingPersistenceContainer.syncedModelTypes)
        let local = names(TrainingPersistenceContainer.localModelTypes)

        #expect(synced.isDisjoint(with: local))
        #expect(synced.union(local) == names(TrainingPersistenceContainer.modelTypes))
    }

    @Test("nothing read from HealthKit, or derived from it, is in the synced set")
    func healthDataIsLocal() {
        let synced = names(TrainingPersistenceContainer.syncedModelTypes)

        for healthModel in [
            "ActivityRecord", "DeletedActivitySourceRecord", "ActivityJoinRecord", "AthleteProfileRecord",
            "FitnessMetricsRecord", "FitnessMetricsCacheStateRecord",
        ] {
            #expect(!synced.contains(healthModel), "\(healthModel) would sync to iCloud")
        }
        #expect(synced.contains("AthletePreferencesRecord"))
    }

    // MARK: The synced preferences

    @Test("the synced record holds the athlete's preferences and none of the health-derived profile")
    func syncedRecordHasNoHealthFields() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        var profile = AthleteProfile.fixture(name: "Alex", sex: .female)
        profile.dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
        profile.avatarImageData = Data([1, 2, 3])
        try await store.save(profile)

        let record = try #require(ModelContext(container).fetch(FetchDescriptor<AthletePreferencesRecord>()).first)
        let object = try #require(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])

        #expect(object["name"] as? String == "Alex")
        #expect(object["avatarImageData"] != nil)
        for healthKey in ["sex", "dateOfBirth", "heartRateZoneHistory", "id"] {
            #expect(object[healthKey] == nil, "\(healthKey) would sync to iCloud")
        }
    }

    @Test("a preference changed in the synced record (another device's edit) shows in the profile; health fields stay local")
    func syncedPreferencesWin() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        var profile = AthleteProfile.fixture(name: "Alex", sex: .female, timeZoneIdentifier: "UTC")
        profile.dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
        try await store.save(profile)

        // The other device renamed the athlete and changed the week start.
        let context = ModelContext(container)
        let record = try #require(context.fetch(FetchDescriptor<AthletePreferencesRecord>()).first)
        var preferences = try record.toPreferences()
        preferences.name = "Sam"
        preferences.weekStartsOn = .sunday
        try record.update(from: preferences)
        try context.save()

        let fetched = try #require(await store.athleteProfile())
        #expect(fetched.name == "Sam")
        #expect(fetched.weekStartsOn == .sunday)
        #expect(fetched.sex == .female)
        #expect(fetched.dateOfBirth == profile.dateOfBirth)
        #expect(fetched.heartRateZoneHistory == profile.heartRateZoneHistory)
    }

    @Test("saving twice keeps one preferences record")
    func oneRecord() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        try await store.save(AthleteProfile.fixture(name: "A"))
        try await store.save(AthleteProfile.fixture(name: "B"))

        #expect(try ModelContext(container).fetch(FetchDescriptor<AthletePreferencesRecord>()).count == 1)
    }

    // MARK: Migrating a store written before the split

    /// Writes a store the way this package did before the split: one store, every model but the
    /// preferences record, no CloudKit.
    private func writeLegacyStore(
        in directory: URL, activity: Activity, plan: PlannedActivity, profile: AthleteProfile, metrics: FitnessMetrics? = nil
    ) throws {
        let legacyTypes = TrainingPersistenceContainer.modelTypes.filter { $0 != AthletePreferencesRecord.self }
        let container = try ModelContainer(
            for: Schema(legacyTypes),
            configurations: [ModelConfiguration(
                "default", schema: Schema(legacyTypes),
                url: LegacyStoreMigration.syncedStoreURL(in: directory), cloudKitDatabase: .none
            )]
        )
        let context = ModelContext(container)
        context.insert(try ActivityRecord(activity: activity))
        context.insert(DeletedActivitySourceRecord(sourceKey: "healthKit:gone", deletedAt: day(0)))
        context.insert(try ActivityJoinRecord(joinID: UUID(), componentIDs: [UUID(), UUID()]))
        context.insert(try PlannedActivityRecord(plan: plan))
        let profileRecord = AthleteProfileRecord()
        try profileRecord.update(from: profile)
        profileRecord.importAnchorData = Data([7, 7])
        context.insert(profileRecord)
        if let metrics {
            context.insert(try FitnessMetricsRecord(metrics: metrics))
        }
        try context.save()
    }

    @Test("an old store's activities, tombstones, joins, profile and anchor move to the local store; plans stay")
    func migratesAnOldStore() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(1), duration: 1800,
            heartRate: [HeartRateSample(time: day(1), bpm: 150)], linkedPlanID: UUID()
        )
        let plan = PlannedActivity(workoutID: UUID(), date: day(2))
        var profile = AthleteProfile.fixture(name: "Alex", sex: .female)
        profile.dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
        try writeLegacyStore(in: directory, activity: activity, plan: plan, profile: profile)

        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)
        let store = SwiftDataStore(modelContainer: container)

        #expect(try await store.activity(id: activity.id) == activity)
        #expect(try await store.tombstonedSources(among: [.manual]).isEmpty)
        #expect(try await store.plan(id: plan.id) == plan)
        #expect(try await store.athleteProfile() == profile)
        #expect(try await store.importAnchor() == ImportAnchor(data: Data([7, 7])))
        #expect(try ModelContext(container).fetch(FetchDescriptor<ActivityJoinRecord>()).count == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<DeletedActivitySourceRecord>()).count == 1)
        // The preferences were given to the synced store.
        #expect(try ModelContext(container).fetch(FetchDescriptor<AthletePreferencesRecord>()).count == 1)
    }

    @Test("the old file is kept as a backup before its local-only tables are dropped")
    func keepsABackupOfTheOldStore() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(1), duration: 1800)
        try writeLegacyStore(
            in: directory, activity: activity, plan: PlannedActivity(workoutID: UUID(), date: day(2)),
            profile: AthleteProfile.fixture()
        )

        _ = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)

        // The backup is a complete old store: opened as one, it still has the activity the split
        // container removed from the original file.
        let legacyTypes = TrainingPersistenceContainer.modelTypes.filter { $0 != AthletePreferencesRecord.self }
        let backup = try ModelContainer(
            for: Schema(legacyTypes),
            configurations: [ModelConfiguration(
                "default", schema: Schema(legacyTypes), url: LegacyStoreMigration.backupURL(in: directory),
                cloudKitDatabase: .none
            )]
        )
        #expect(try ModelContext(backup).fetch(FetchDescriptor<ActivityRecord>()).count == 1)
        #expect(try ModelContext(backup).fetch(FetchDescriptor<PlannedActivityRecord>()).count == 1)
    }

    @Test("an interrupted migration resumes without copying again from an emptied old store")
    func resumesAnInterruptedMigration() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(1), duration: 1800)
        try writeLegacyStore(
            in: directory, activity: activity, plan: PlannedActivity(workoutID: UUID(), date: day(2)),
            profile: AthleteProfile.fixture()
        )

        // The first launch got as far as copying, and the old file then lost its local-only rows
        // (emptied here by hand: how much of it the split container removes is SwiftData's business),
        // before the final step.
        try LegacyStoreMigration.copyLocalDataIfNeeded(in: directory)
        do {
            let legacyTypes = TrainingPersistenceContainer.modelTypes.filter { $0 != AthletePreferencesRecord.self }
            let old = try ModelContainer(
                for: Schema(legacyTypes),
                configurations: [ModelConfiguration(
                    "default", schema: Schema(legacyTypes),
                    url: LegacyStoreMigration.syncedStoreURL(in: directory), cloudKitDatabase: .none
                )]
            )
            let context = ModelContext(old)
            try context.delete(model: ActivityRecord.self)
            try context.delete(model: DeletedActivitySourceRecord.self)
            try context.delete(model: ActivityJoinRecord.self)
            try context.delete(model: AthleteProfileRecord.self)
            try context.save()
        }

        // The next launch must not copy again from the now-emptied old file over the good copy.
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)
        let store = SwiftDataStore(modelContainer: container)

        #expect(try await store.activity(id: activity.id) == activity)
        #expect(try await store.athleteProfile() != nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AthletePreferencesRecord>()).count == 1)
    }

    @Test("the fitness-metrics cache isn't carried over: it rebuilds from the activities")
    func metricsCacheIsNotCopied() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLegacyStore(
            in: directory, activity: Activity(source: .manual, sport: .running, start: day(1), duration: 600),
            plan: PlannedActivity(workoutID: UUID(), date: day(2)), profile: AthleteProfile.fixture(),
            metrics: FitnessMetrics(
                day: day(1), load: 10, ctl: 5, atl: 6, tsb: -1,
                monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
            )
        )

        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)

        #expect(try ModelContext(container).fetch(FetchDescriptor<FitnessMetricsRecord>()).isEmpty)
    }

    @Test("opening the container again after migrating copies nothing twice")
    func migrationRunsOnce() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(1), duration: 1800)
        try writeLegacyStore(
            in: directory, activity: activity, plan: PlannedActivity(workoutID: UUID(), date: day(2)),
            profile: AthleteProfile.fixture()
        )
        do {
            _ = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)
        }

        let again = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)
        let context = ModelContext(again)

        #expect(try context.fetch(FetchDescriptor<ActivityRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DeletedActivitySourceRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AthletePreferencesRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PlannedActivityRecord>()).count == 1)
    }

    @Test("a fresh install has nothing to migrate, and what it saves is not taken for an old store later")
    func freshInstall() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activity = Activity(source: .manual, sport: .running, start: day(1), duration: 600)
        do {
            let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)
            try await SwiftDataStore(modelContainer: container).upsert([activity])
        }

        let again = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, storeDirectory: directory)

        #expect(try await SwiftDataStore(modelContainer: again).activity(id: activity.id) == activity)
    }
}
