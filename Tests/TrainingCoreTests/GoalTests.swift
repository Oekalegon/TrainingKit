import Foundation
import Testing
@testable import TrainingCore

@Suite("Goal")
struct GoalTests {
    @Test("every target kind survives a JSON round trip")
    func codableRoundTrip() throws {
        let goals = [
            Goal(name: "Sub-20 5k", target: .time(sport: .running, distanceMeters: 5000, seconds: 1200), notes: "Parkrun"),
            Goal(name: "Ride 5000 km", target: .volume(sport: .cycling, measure: .distanceMeters, amount: 5_000_000, per: .year)),
            Goal(name: "Train 5 hours a week", target: .volume(sport: nil, measure: .durationSeconds, amount: 18_000, per: .week)),
            Goal(name: "Enjoy running again", target: .freeText),
        ]

        let decoded = try JSONDecoder().decode([Goal].self, from: JSONEncoder().encode(goals))

        #expect(decoded == goals)
    }
}
