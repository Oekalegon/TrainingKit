import Foundation
import Testing
@testable import TrainingCore

@Suite("Activity.dateRange")
struct ActivityDateRangeTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("dateRange spans start to start + duration for a positive duration")
    func positiveDuration() {
        let activity = Activity(source: .manual, sport: .running, start: start, duration: 1800)

        #expect(activity.dateRange == start...start.addingTimeInterval(1800))
    }

    @Test("dateRange doesn't trap for a negative duration, clamping to a zero-length range instead")
    func negativeDurationDoesNotTrap() {
        let activity = Activity(source: .manual, sport: .running, start: start, duration: -600)

        #expect(activity.dateRange == start...start)
    }
}
