import Foundation
import Testing
@testable import TrainingCore

@Suite("Activity battery use (WATCH-119)")
struct ActivityBatteryTests {
    private func activity(duration: TimeInterval, start: Double?, end: Double?) -> Activity {
        Activity(
            source: .manual, sport: .running, start: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration, batteryStart: start, batteryEnd: end)
    }

    @Test("the drain per hour is the drop over the duration")
    func drain() throws {
        let drain = try #require(activity(duration: 1800, start: 0.9, end: 0.84).batteryDrainPerHour)
        #expect(abs(drain - 0.12) < 1e-9)
    }

    @Test("no drain without both levels, for a short workout, a level that did not drop, or one that rose")
    func noDrain() {
        #expect(activity(duration: 3600, start: nil, end: nil).batteryDrainPerHour == nil)
        #expect(activity(duration: 3600, start: 0.9, end: nil).batteryDrainPerHour == nil)
        #expect(activity(duration: 600, start: 0.9, end: 0.8).batteryDrainPerHour == nil)
        #expect(activity(duration: 3600, start: 0.9, end: 0.895).batteryDrainPerHour == nil)
        #expect(activity(duration: 3600, start: 0.5, end: 0.8).batteryDrainPerHour == nil)
    }

    @Test("the levels survive encoding, and an activity saved without them still loads")
    func codable() throws {
        let original = activity(duration: 3600, start: 0.9, end: 0.8)
        let decoded = try JSONDecoder().decode(Activity.self, from: JSONEncoder().encode(original))
        #expect(decoded.batteryStart == 0.9 && decoded.batteryEnd == 0.8)

        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["batteryStart"] = nil
        json["batteryEnd"] = nil
        let old = try JSONDecoder().decode(Activity.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.batteryStart == nil && old.batteryEnd == nil)
    }
}
