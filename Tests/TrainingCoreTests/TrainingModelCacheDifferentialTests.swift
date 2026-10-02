import Foundation
import Testing
@testable import TrainingCore

/// The cache-aware recompute must publish the same CTL/ATL/TSB as a from-scratch computation,
/// however the cache got into its current state.
@MainActor
@Suite("TrainingModel cache vs from-scratch", .serialized)
struct TrainingModelCacheDifferentialTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func activity(onDay offset: Int, hour: Int = 9, minutes: Double = 30) -> Activity {
        let start = calendar.date(byAdding: .hour, value: hour, to: day(offset))!
        return Activity(
            source: .healthKit(UUID()), sport: .running, start: start,
            duration: minutes * 60, perceivedExertion: 5
        )
    }

    private func expectMatchesFromScratch(
        _ model: TrainingModel, stores: StoreSet, range: ClosedRange<Date>, today: Date, label: String
    ) async throws {
        // The same stores without a cache: `TrainingModel` then recomputes the whole series from
        // the activities every time, which is the reference the cache has to agree with.
        let uncachedStores = StoreSet(
            activityStore: stores.activityStore, planStore: stores.planStore,
            workoutStore: stores.workoutStore, cycleStore: stores.cycleStore,
            raceStore: stores.raceStore, athleteStore: stores.athleteStore
        )
        let reference = TrainingModel(stores: uncachedStores, athlete: model.athlete)
        // The whole history, not just `range`: the reference has to be warm where `range` starts.
        try await reference.load(in: day(-30)...range.upperBound, asOf: today)
        let expected = reference.metrics
        for want in expected where range.contains(want.day) {
            let rows = model.metrics.filter { $0.day == want.day }
            #expect(rows.count == 1, Comment(rawValue: "\(label): \(rows.count) rows for day \(want.day)"))
            guard let got = rows.first else { continue }
            #expect(abs(got.ctl - want.ctl) < 1e-6, Comment(rawValue: "\(label): CTL on \(want.day): \(got.ctl) vs \(want.ctl)"))
            #expect(abs(got.atl - want.atl) < 1e-6, Comment(rawValue: "\(label): ATL on \(want.day): \(got.atl) vs \(want.atl)"))
            #expect(abs(got.tsb - want.tsb) < 1e-6, Comment(rawValue: "\(label): TSB on \(want.day): \(got.tsb) vs \(want.tsb)"))
        }
    }

    @Test("a late import after the cache fell several days behind matches a from-scratch series")
    func lateImportAfterCacheGap() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, fitnessMetricsCacheStore: store
        )
        for offset in 0...10 where offset != 5 && offset != 6 {
            try await store.upsert([activity(onDay: offset)])
        }
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        // Last app run: day 11 was "today", so the cache is final through day 10.
        let window = day(8)...day(16)
        try await model.load(in: window, asOf: day(11))

        // Days 11-13 pass with the app closed. HealthKit then delivers a day-13 activity (earliest
        // affected date = day 13) and a few activities for days 12 that the app never saw.
        let late = ImportResult(upserted: [activity(onDay: 13, hour: 21)], deletedSources: [], anchor: nil)
        try await model.importActivities(from: LateImporter(result: late), asOf: day(14))
        try await expectMatchesFromScratch(model, stores: stores, range: window, today: day(14), label: "gap")
    }
}

private actor LateImporter: ActivityImporting {
    let result: ImportResult
    init(result: ImportResult) { self.result = result }
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult { result }
}
