import Foundation
import Testing
@testable import TrainingCore

@Suite("ActivityStore.activityListItems (InMemoryStore, MVP2-129)")
struct InMemoryStoreListItemTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    @Test("the default matches activities(in:) without samples, joins and nil optionals included")
    func matchesActivities() async throws {
        let store = InMemoryStore()
        let planID = UUID()
        let hr = (0..<50).map { HeartRateSample(time: day(0).addingTimeInterval(Double($0)), bpm: 140) }
        let run = Activity(
            source: .manual, sport: .running, start: day(1), duration: 1800, distanceMeters: 5000,
            heartRate: hr, linkedPlanID: planID
        )
        let bare = Activity(source: .manual, sport: .cycling, start: day(3), duration: 600)
        let first = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(5), duration: 900)
        let second = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(6), duration: 900)
        let outOfRange = Activity(source: .manual, sport: .running, start: day(50), duration: 600)
        try await store.upsert([run, bare, first, second, outOfRange])
        let joined = try #require(Activity.joined([first, second]))
        try await store.saveJoin(joined, components: [first.id, second.id], replacing: [])

        let items = try await store.activityListItems(in: day(0)...day(10))
        let full = try await store.activities(in: day(0)...day(10))

        #expect(Set(items) == Set(full.map(ActivityListItem.init)))
        #expect(items.count == 3)
        #expect(items.first { $0.id == run.id }?.linkedPlanID == planID)
        #expect(items.first { $0.id == bare.id }?.distanceMeters == nil)
        #expect(try await store.activityListItems(in: day(20)...day(30)).isEmpty)
    }
}
