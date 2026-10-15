import Foundation
import Testing
import TrainingCore
@testable import TrainingPersistence

@Suite("WorkoutPurpose + SwiftData")
struct SwiftDataWorkoutPurposeTests {
    @Test("a workout and a template keep their purpose through the records (MVP2-153)")
    func purposeSurvivesRecords() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let template = BuiltInWorkoutTemplates.maxHRTest
        let workout = try template.instantiate()

        try await store.upsert([template])
        try await store.upsert([workout])

        #expect(try await store.template(id: template.id)?.purpose == .maxHRTest)
        #expect(try await store.workout(id: workout.id)?.purpose == .maxHRTest)
    }
}

@Suite("Field-test sources + SwiftData")
struct SwiftDataFieldTestSourceTests {
    @Test("an athlete profile keeps the field-test sources of its heart-rate settings (MVP2-154)")
    func sourcesSurviveProfileRecord() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let id = UUID()
        var profile = AthleteProfile.fixture()
        profile = profile.settingMaxHeartRate(to: 171, from: Date(timeIntervalSince1970: 1_700_000_000), source: .fieldTest(activityID: id))
        profile = profile.settingLactateThresholdHeartRate(
            to: 162, from: Date(timeIntervalSince1970: 1_700_000_000), source: .fieldTest(activityID: id)
        )

        try await store.save(profile)

        let loaded = try #require(try await store.athleteProfile())
        let settings = try #require(loaded.currentHeartRateZoneSettings)
        #expect(settings.maxHeartRateSource == .fieldTest(activityID: id))
        #expect(settings.lactateThresholdSource == .fieldTest(activityID: id))
        #expect(settings.maxHeartRateBPM == 171)
    }

    @Test("a lab-test source survives the profile record")
    func labTestSurvivesProfileRecord() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        var profile = AthleteProfile.fixture()
        profile.heartRateZoneHistory[0].maxHeartRateSource = .labTest(measuredOn: Date(timeIntervalSince1970: 1_690_000_000))
        profile.heartRateZoneHistory[0].lactateThresholdHeartRateBPM = 165
        profile.heartRateZoneHistory[0].lactateThresholdSource = .labTest(measuredOn: Date(timeIntervalSince1970: 1_690_000_000))

        try await store.save(profile)

        let settings = try #require(try await store.athleteProfile()?.currentHeartRateZoneSettings)
        #expect(settings.maxHeartRateSource == .labTest(measuredOn: Date(timeIntervalSince1970: 1_690_000_000)))
        #expect(settings.lactateThresholdSource == .labTest(measuredOn: Date(timeIntervalSince1970: 1_690_000_000)))
    }
}
