import Foundation
import Testing
@testable import TrainingCore

@Suite("DayAssigner")
struct DayAssignerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    /// Monday 5 October 2026, start of day.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    private func micro(days: Int) -> ClosedRange<Date> { day(0)...day(days - 1) }

    /// Availability with the given weekdays free in the morning only.
    private func availability(_ weekdays: [Weekday], slots: Set<DaySlot> = [.morning]) -> RunAvailability {
        RunAvailability(slots: Dictionary(uniqueKeysWithValues: weekdays.map { ($0, slots) }))
    }

    private let allWeek: [Weekday] = Weekday.allCases
    private let paradigm = TrainingParadigm.polarized8020

    private func assign(_ avail: RunAvailability, hard: Int, long: Int, days: Int = 7, preceding: [Date] = [], paradigm: TrainingParadigm? = nil) -> DayAssignmentResult {
        DayAssigner(paradigm: paradigm).assign(micro: micro(days: days), availability: avail, hardCount: hard, longCount: long, preceding: preceding, calendar: calendar)
    }

    private func offsets(_ result: DayAssignmentResult, _ type: RunType) -> [Int] {
        result.assignments.filter { $0.runType == type }.map { calendar.dateComponents([.day], from: monday, to: $0.day).day! }
    }

    @Test("every free run is filled: the requested long and hard sessions, the rest easy")
    func fills() {
        let result = assign(availability(allWeek), hard: 2, long: 1)
        #expect(result.assignments.count == 7 && result.dropped.isEmpty)
        #expect(offsets(result, .long).count == 1)
        #expect(result.assignments.filter { [.interval, .threshold].contains($0.runType) }.count == 2)
        #expect(offsets(result, .easy).count == 4)
        #expect(result.assignments.map(\.day) == result.assignments.map(\.day).sorted())
    }

    @Test("days without availability get nothing; zero requested sessions leaves only easy runs")
    func unavailable() {
        let result = assign(availability([.monday, .wednesday]), hard: 0, long: 0)
        #expect(offsets(result, .easy) == [0, 2] && result.assignments.count == 2)
        #expect(assign(RunAvailability(), hard: 1, long: 1).dropped.map(\.reason) == [.noFreeDay, .noFreeDay])
    }

    @Test("a long run goes to the day that names long, even when an earlier day is free")
    func longPrefersNamedDay() {
        var avail = availability(allWeek)
        avail.setRunTypes([.long], on: .saturday)
        #expect(offsets(assign(avail, hard: 0, long: 1), .long) == [5])
    }

    @Test("without a named day, the long run goes to the day with most free parts, then the earliest")
    func longPrefersMostParts() {
        var avail = availability(allWeek)
        avail[.thursday] = [.morning, .evening]
        avail.setRuns(2, on: .thursday)
        #expect(offsets(assign(avail, hard: 0, long: 1), .long) == [3])
        #expect(offsets(assign(availability(allWeek), hard: 0, long: 1), .long) == [0])
    }

    @Test("a long run needs a part where one is possible; none gives noLongRunSlot")
    func longNeedsSlot() {
        var avail = availability([.monday, .tuesday])
        avail[.monday, .morning] = SlotOptions(longRunPossible: false)
        #expect(offsets(assign(avail, hard: 0, long: 1), .long) == [1])
        avail[.tuesday, .morning] = SlotOptions(longRunPossible: false)
        let result = assign(avail, hard: 0, long: 1)
        #expect(result.dropped == [DroppedSession(kind: .long, reason: .noLongRunSlot)])
        #expect(offsets(result, .long).isEmpty)
    }

    @Test("a session no day allows is runTypeNotAllowed, not noFreeDay")
    func typeNotAllowed() {
        var avail = availability([.monday])
        avail.setRunTypes([.long, .interval, .threshold], on: .tuesday)
        let result = assign(avail, hard: 1, long: 1)
        #expect(result.dropped == [DroppedSession(kind: .long, reason: .runTypeNotAllowed), DroppedSession(kind: .hard, reason: .runTypeNotAllowed)])
        #expect(assign(RunAvailability(), hard: 1, long: 1).dropped.allSatisfy { $0.reason == .noFreeDay })
    }

    @Test("a long run is not put on a day that names other run types only")
    func longRespectsNamedTypes() {
        var avail = availability([.monday, .tuesday])
        avail.setRunTypes([.long], on: .tuesday)
        avail.setRunTypes([.interval], on: .monday)
        let result = assign(avail, hard: 0, long: 1)
        #expect(offsets(result, .long) == [1])
        #expect(offsets(result, .interval).isEmpty) // not requested; named types do not force sessions
    }

    @Test("hard sessions go to days naming a hard type first, using that type")
    func hardPrefersNamed() {
        var avail = availability(allWeek)
        avail.setRunTypes([.threshold], on: .thursday)
        let result = assign(avail, hard: 1, long: 0)
        #expect(offsets(result, .threshold) == [3])
    }

    @Test("hard sessions respect the paradigm's spacing, counting the long run, and across the micro start")
    func spacing() {
        let result = assign(availability(allWeek), hard: 2, long: 1, paradigm: paradigm)
        let spaced = (offsets(result, .long) + offsets(result, .interval) + offsets(result, .threshold)).sorted()
        #expect(spaced.count == 3 && zip(spaced, spaced.dropFirst()).allSatisfy { $1 - $0 >= 2 })

        // The previous micro ended with a hard session the day before Monday: Monday is too close.
        let across = assign(availability(allWeek), hard: 1, long: 0, preceding: [day(-1)], paradigm: paradigm)
        #expect(offsets(across, .interval) == [1])
    }

    @Test("a hard session with no day far enough from the others is dropped for spacing")
    func spacingDrop() {
        let result = assign(availability([.monday, .tuesday]), hard: 2, long: 0, paradigm: paradigm)
        #expect(result.dropped == [DroppedSession(kind: .hard, reason: .spacing)])
        #expect(offsets(result, .interval).count == 1 && offsets(result, .easy).count == 1)
    }

    @Test("the paradigm's hard limit for the micro length drops the extra hard sessions; 10- and 14-day micros allow more")
    func hardLimit() {
        let seven = assign(availability(allWeek), hard: 3, long: 0, paradigm: paradigm)
        #expect(seven.dropped == [DroppedSession(kind: .hard, reason: .hardLimit)])
        let ten = assign(availability(allWeek), hard: 3, long: 0, days: 10, paradigm: paradigm)
        #expect(ten.dropped.isEmpty && ten.assignments.count == 10)
        let fourteen = assign(availability(allWeek), hard: 4, long: 0, days: 14, paradigm: paradigm)
        #expect(fourteen.dropped.isEmpty && fourteen.assignments.count == 14)
    }

    @Test("without a paradigm there is no spacing or limit")
    func noParadigm() {
        let result = assign(availability(allWeek), hard: 5, long: 0)
        #expect(result.dropped.isEmpty && offsets(result, .interval).count == 5)
    }

    @Test("a two-a-day uses two free parts in morning, afternoon, evening order; the hard run takes the first")
    func twoADay() {
        var avail = availability([.monday], slots: [.morning, .evening])
        avail.setRuns(2, on: .monday)
        let result = assign(avail, hard: 1, long: 0)
        #expect(result.assignments.map(\.slot) == [.morning, .evening])
        #expect(result.assignments.map(\.runType) == [.interval, .easy])
        // One run a day uses one part only.
        var one = availability([.monday], slots: [.morning, .evening])
        one.setRuns(1, on: .monday)
        #expect(assign(one, hard: 0, long: 0).assignments.count == 1)
    }

    @Test("recovery fills a day that allows recovery but not easy; a day allowing neither gets nothing")
    func recoveryFill() {
        var avail = availability([.monday, .tuesday, .wednesday])
        avail.setRunTypes([.recovery], on: .monday)
        avail.setRunTypes([.easy, .recovery], on: .tuesday)
        let all = assign(avail, hard: 0, long: 0)
        // Easy and recovery are named for other days, so Wednesday allows neither and gets nothing.
        #expect(offsets(all, .recovery) == [0] && offsets(all, .easy) == [1] && all.assignments.count == 2)
        // Everything but easy and recovery is named elsewhere, so no day other than Tuesday allows them.
        var narrow = availability([.monday])
        narrow.setRunTypes([.easy, .recovery], on: .tuesday)
        narrow.setRunTypes([.threshold], on: .monday)
        #expect(assign(narrow, hard: 0, long: 0).assignments.isEmpty)
    }

    @Test("a custom hardTypes order picks the type; a long run and a hard session may share a two-a-day without a paradigm")
    func customHardTypesAndSameDay() {
        var avail = availability([.monday], slots: [.morning, .evening])
        avail.setRuns(2, on: .monday)
        let result = DayAssigner(hardTypes: [.threshold]).assign(micro: micro(days: 1), availability: avail, hardCount: 1, longCount: 1, calendar: calendar)
        #expect(Set(result.assignments.map(\.runType)) == [.long, .threshold])
        #expect(result.dropped.isEmpty)
        // With a spacing paradigm the same day is too close.
        let spaced = DayAssigner(paradigm: paradigm, hardTypes: [.threshold]).assign(micro: micro(days: 1), availability: avail, hardCount: 1, longCount: 1, calendar: calendar)
        #expect(spaced.dropped == [DroppedSession(kind: .hard, reason: .spacing)])
    }

    @Test("weekdays map by date, so a 10-day micro that crosses a week uses each weekday twice")
    func tenDayMicro() {
        let result = assign(availability([.monday, .thursday]), hard: 0, long: 0, days: 10)
        #expect(offsets(result, .easy) == [0, 3, 7])
    }

    @Test("a daylight-saving change inside the micro does not shift the days")
    func daylightSaving() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))! // 25 Oct: clocks go back
        let range = start...calendar.date(byAdding: .day, value: 3, to: start)!
        let result = DayAssigner().assign(micro: range, availability: availability(allWeek), hardCount: 0, longCount: 0, calendar: calendar)
        #expect(result.assignments.count == 4)
        #expect(result.assignments.allSatisfy { calendar.startOfDay(for: $0.day) == $0.day })
    }

    @Test("a race day gets nothing and the other days are filled as before")
    func raceDays() {
        let result = DayAssigner().assign(
            micro: micro(days: 7), availability: availability(allWeek), hardCount: 1, longCount: 1,
            raceDays: [day(6)], calendar: calendar
        )
        #expect(result.assignments.count == 6 && result.dropped.isEmpty)
        #expect(!result.assignments.contains { calendar.isDate($0.day, inSameDayAs: day(6)) })
    }

    @Test("a long run that would fall on a race day goes to another day, or is dropped when there is none")
    func longRunAvoidsRaceDay() {
        let onlySunday = DayAssigner().assign(
            micro: micro(days: 7), availability: availability([.sunday]), hardCount: 0, longCount: 1,
            raceDays: [day(6)], calendar: calendar
        )
        #expect(onlySunday.assignments.isEmpty)
        #expect(onlySunday.dropped.map(\.reason) == [.noFreeDay])
    }
}
