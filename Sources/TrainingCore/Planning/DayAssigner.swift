import Foundation

/// Places the runs of one micro on its days and day parts, from the athlete's availability.
///
/// The athlete states how many hard and how many long sessions a micro gets; every other free run
/// (``RunAvailability/runs(on:)`` per day) is filled with an easy run, or a recovery run where easy
/// is not allowed. Placement is deterministic:
/// 1. **Long runs** first, on a day that allows ``RunType/long`` and has a free part where a long
///    run is possible (``SlotOptions/longRunPossible``). Days that name `.long` come first, then
///    days with more free parts, then the earlier date.
/// 2. **Hard sessions** next, on a day that allows one of ``hardTypes`` (the first allowed type in
///    that order is used). Days that name a hard type come first, then the earlier date.
/// 3. **Easy runs** (or recovery) in every free run left.
///
/// A day allows a run type when ``RunAvailability/runTypes(on:)`` contains it. Hard sessions, and
/// long runs when ``TrainingParadigm/spacesLongRunsAsHard`` is set, keep at least
/// ``TrainingParadigm/minDaysBetweenHardSessions`` days from each other and from the sessions of
/// the preceding micro. A micro never gets more hard sessions than
/// ``TrainingParadigm/maxHardSessionsPerMicro`` allows for its length. Within a day, a run takes
/// the first free part in the order morning, afternoon, evening (a long run the first one where a
/// long run is possible). A session that cannot be placed is returned as dropped, never
/// substituted. Track availability is ignored: an interval session does not need a track.
public struct DayAssigner: Sendable, Hashable {
    /// The paradigm whose hard-session rules apply; `nil` for no spacing or limit.
    public var paradigm: TrainingParadigm?
    /// The run types a hard session may take, in order of preference; defaults to interval, threshold.
    public var hardTypes: [RunType]

    /// Creates a day assigner.
    ///
    /// - Parameters:
    ///   - paradigm: The paradigm whose hard-session rules apply; defaults to `nil` (none).
    ///   - hardTypes: The run types a hard session may take, in order of preference; defaults to
    ///     `[.interval, .threshold]`.
    public init(paradigm: TrainingParadigm? = nil, hardTypes: [RunType] = [.interval, .threshold]) {
        self.paradigm = paradigm
        self.hardTypes = hardTypes
    }

    /// Places the runs of one micro.
    ///
    /// - Parameters:
    ///   - micro: The micro's days, day-granular (start of day) in `calendar`'s timezone.
    ///   - availability: When the athlete can run, per weekday.
    ///   - hardCount: How many hard sessions the micro should get.
    ///   - longCount: How many long runs the micro should get.
    ///   - preceding: The days of the hard sessions (and long runs, if the paradigm spaces them as
    ///     hard) just before the micro, so spacing holds across its start; defaults to none.
    ///   - calendar: The athlete's calendar, which maps days to weekdays.
    /// - Returns: The placed runs and the sessions that could not be placed. A day without free
    ///   runs, or outside the availability, gets nothing.
    public func assign(
        micro: ClosedRange<Date>,
        availability: RunAvailability,
        hardCount: Int,
        longCount: Int,
        preceding: [Date] = [],
        calendar: Calendar
    ) -> DayAssignmentResult {
        var days: [Day] = []
        var cursor = micro.lowerBound
        while cursor <= micro.upperBound {
            if let weekday = Weekday(rawValue: calendar.component(.weekday, from: cursor)) {
                let runs = availability.runs(on: weekday)
                if runs > 0 {
                    days.append(Day(date: cursor, weekday: weekday, capacity: runs, freeSlots: DaySlot.allCases.filter { availability[weekday].contains($0) }))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var spaced = preceding
        var placed: [DayAssignment] = []
        var dropped: [DroppedSession] = []
        let minGap = paradigm?.minDaysBetweenHardSessions
        let spacesLong = paradigm?.spacesLongRunsAsHard ?? false

        func spacingAllows(_ date: Date) -> Bool {
            guard let minGap else { return true }
            return spaced.allSatisfy { abs(calendar.dateComponents([.day], from: $0, to: date).day ?? Int.max) >= minGap }
        }

        for _ in 0..<max(longCount, 0) {
            let withCapacity = days.indices.filter { days[$0].capacity > 0 }
            let allowing = withCapacity.filter { availability.runTypes(on: days[$0].weekday).contains(.long) }
            // Each candidate with the part its long run would take.
            let withSlot: [(index: Int, slot: DaySlot)] = allowing.compactMap { index in
                days[index].freeSlots.first { availability[days[index].weekday, $0].longRunPossible }.map { (index, $0) }
            }
            let candidates = withSlot.filter { !spacesLong || spacingAllows(days[$0.index].date) }
            let best = candidates.min { lhs, rhs in
                let (named0, named1) = (availability.dayRunTypes[days[lhs.index].weekday]?.contains(.long) == true, availability.dayRunTypes[days[rhs.index].weekday]?.contains(.long) == true)
                if named0 != named1 { return named0 }
                if days[lhs.index].freeSlots.count != days[rhs.index].freeSlots.count { return days[lhs.index].freeSlots.count > days[rhs.index].freeSlots.count }
                return days[lhs.index].date < days[rhs.index].date
            }
            guard let best else {
                let reason: DropReason = withCapacity.isEmpty ? .noFreeDay : allowing.isEmpty ? .runTypeNotAllowed : withSlot.isEmpty ? .noLongRunSlot : .spacing
                dropped.append(DroppedSession(kind: .long, reason: reason))
                continue
            }
            days[best.index].take(best.slot)
            placed.append(DayAssignment(day: days[best.index].date, slot: best.slot, runType: .long))
            if spacesLong { spaced.append(days[best.index].date) }
        }

        let hardLimit = paradigm?.maxHardSessionsPerMicro[Self.length(of: micro, calendar: calendar)]
        var hardPlaced = 0
        for _ in 0..<max(hardCount, 0) {
            if let hardLimit, hardPlaced >= hardLimit {
                dropped.append(DroppedSession(kind: .hard, reason: .hardLimit))
                continue
            }
            let withCapacity = days.indices.filter { days[$0].capacity > 0 }
            // Each candidate day with the type and part its hard session would take.
            let allowing: [(index: Int, type: RunType, slot: DaySlot, named: Bool)] = withCapacity.compactMap { index in
                let allowed = availability.runTypes(on: days[index].weekday)
                let named = availability.dayRunTypes[days[index].weekday] ?? []
                let namedType = hardTypes.first { named.contains($0) }
                guard let type = namedType ?? hardTypes.first(where: { allowed.contains($0) }), let slot = days[index].freeSlots.first else { return nil }
                return (index, type, slot, namedType != nil)
            }
            let best = allowing.filter { spacingAllows(days[$0.index].date) }.min { lhs, rhs in
                if lhs.named != rhs.named { return lhs.named }
                return days[lhs.index].date < days[rhs.index].date
            }
            guard let best else {
                dropped.append(DroppedSession(kind: .hard, reason: withCapacity.isEmpty ? .noFreeDay : allowing.isEmpty ? .runTypeNotAllowed : .spacing))
                continue
            }
            days[best.index].take(best.slot)
            placed.append(DayAssignment(day: days[best.index].date, slot: best.slot, runType: best.type))
            spaced.append(days[best.index].date)
            hardPlaced += 1
        }

        for index in days.indices {
            let allowed = availability.runTypes(on: days[index].weekday)
            let type: RunType? = allowed.contains(.easy) ? .easy : allowed.contains(.recovery) ? .recovery : nil
            guard let type else { continue }
            while days[index].capacity > 0, let slot = days[index].freeSlots.first {
                days[index].take(slot)
                placed.append(DayAssignment(day: days[index].date, slot: slot, runType: type))
            }
        }

        func rank(_ slot: DaySlot) -> Int { DaySlot.allCases.firstIndex(of: slot) ?? 0 }
        placed.sort { ($0.day, rank($0.slot)) < ($1.day, rank($1.slot)) }
        return DayAssignmentResult(assignments: placed, dropped: dropped)
    }

    private struct Day {
        let date: Date
        let weekday: Weekday
        var capacity: Int
        var freeSlots: [DaySlot]

        mutating func take(_ slot: DaySlot) {
            freeSlots.removeAll { $0 == slot }
            capacity -= 1
        }
    }

    private static func length(of micro: ClosedRange<Date>, calendar: Calendar) -> Int {
        (calendar.dateComponents([.day], from: micro.lowerBound, to: micro.upperBound).day ?? 0) + 1
    }
}
