#if canImport(WorkoutKit)
import WorkoutKit
import Foundation
import Testing
@testable import TrainingWorkoutKit
import TrainingCore

/// An in-memory stand-in for `WorkoutScheduler`, recording what the bridge asked of it.
private actor FakeScheduler {
    var entries: [WorkoutScheduling.Entry]
    private(set) var scheduleCalls = 0
    private(set) var removeCalls = 0

    init(_ entries: [WorkoutScheduling.Entry] = []) {
        self.entries = entries
    }

    func schedule(_ plan: WorkoutPlan, _ date: DateComponents) {
        scheduleCalls += 1
        entries.append(.init(plan: plan, date: date, complete: false))
    }

    func remove(_ plan: WorkoutPlan, _ date: DateComponents) {
        removeCalls += 1
        if let index = entries.firstIndex(where: { $0.plan == plan && $0.date == date }) {
            entries.remove(at: index)
        }
    }

    nonisolated var scheduling: WorkoutScheduling {
        WorkoutScheduling(
            scheduledWorkouts: { await self.entries },
            schedule: { await self.schedule($0, $1) },
            remove: { await self.remove($0, $1) }
        )
    }
}

@Suite("WorkoutKitBridge scheduling")
struct WorkoutKitBridgeSchedulingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    private let easyRun = StructuredWorkout(
        name: "Easy run", sport: .running,
        blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
    )

    private let longRun = StructuredWorkout(
        name: "Long run", sport: .running,
        blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5400))])]
    )

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func day(_ day: Int) -> DateComponents {
        DateComponents(year: 2026, month: 10, day: day)
    }

    private func makeBridge(_ fake: FakeScheduler) -> WorkoutKitBridge {
        WorkoutKitBridge(scheduler: fake.scheduling)
    }

    // MARK: - schedule

    @Test("schedule adds one entry for the plan's day, with the plan's id")
    func scheduleAddsEntry() async throws {
        let fake = FakeScheduler()
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))

        try await makeBridge(fake).schedule(plan, workout: easyRun, calendar: calendar)

        let entries = await fake.entries
        #expect(entries.count == 1)
        #expect(entries[0].plan.id == plan.id)
        #expect(entries[0].date == day(5))
    }

    @Test("schedule uses the athlete's calendar for the day, not UTC")
    func scheduleUsesCalendarDay() async throws {
        let fake = FakeScheduler()
        // 00:30 on 6 October in Amsterdam is still 22:30 on 5 October in UTC: the entry must land on
        // the athlete's day.
        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 0, minute: 30))!
        let plan = PlannedActivity(workoutID: easyRun.id, date: lateEvening)

        try await makeBridge(fake).schedule(plan, workout: easyRun, calendar: calendar)

        #expect(await fake.entries.map(\.date) == [day(6)])
    }

    @Test("Scheduling the same plan again is a no-op")
    func scheduleIsIdempotent() async throws {
        let fake = FakeScheduler()
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let bridge = makeBridge(fake)

        try await bridge.schedule(plan, workout: easyRun, calendar: calendar)
        try await bridge.schedule(plan, workout: easyRun, calendar: calendar)

        #expect(await fake.entries.count == 1)
        #expect(await fake.scheduleCalls == 1)
        #expect(await fake.removeCalls == 0)
    }

    @Test("Scheduling a moved plan removes the entry on its old day")
    func scheduleReplacesMovedPlan() async throws {
        let fake = FakeScheduler()
        var plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let bridge = makeBridge(fake)
        try await bridge.schedule(plan, workout: easyRun, calendar: calendar)

        plan.date = date(7)
        try await bridge.schedule(plan, workout: easyRun, calendar: calendar)

        #expect(await fake.entries.map(\.date) == [day(7)])
    }

    @Test("Scheduling after the workout was edited replaces the stale entry")
    func scheduleReplacesEditedWorkout() async throws {
        let fake = FakeScheduler()
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let bridge = makeBridge(fake)
        try await bridge.schedule(plan, workout: easyRun, calendar: calendar)

        try await bridge.schedule(plan, workout: longRun, calendar: calendar)

        let edited = try bridge.workoutPlan(for: plan, workout: longRun)
        let entries = await fake.entries
        #expect(entries.count == 1)
        #expect(entries[0].plan == edited)
    }

    @Test("A completed entry on the plan's day is kept, even if the workout was edited since")
    func scheduleKeepsCompletedEntry() async throws {
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let original = try WorkoutKitBridge().workoutPlan(for: plan, workout: easyRun)
        let fake = FakeScheduler([.init(plan: original, date: day(5), complete: true)])

        try await makeBridge(fake).schedule(plan, workout: longRun, calendar: calendar)

        let entries = await fake.entries
        #expect(entries.count == 1)
        #expect(entries[0].complete)
        #expect(entries[0].plan == original)
    }

    @Test("A completed entry on another day doesn't stop the plan being scheduled on its new day")
    func scheduleMovesPastCompletedEntryOnOtherDay() async throws {
        var plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let original = try WorkoutKitBridge().workoutPlan(for: plan, workout: easyRun)
        let fake = FakeScheduler([.init(plan: original, date: day(5), complete: true)])

        plan.date = date(7)
        try await makeBridge(fake).schedule(plan, workout: easyRun, calendar: calendar)

        #expect(await fake.entries.map(\.date) == [day(7)])
    }

    @Test("Duplicate entries for one plan collapse to one, preferring the completed one")
    func scheduleRemovesDuplicates() async throws {
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let workoutPlan = try WorkoutKitBridge().workoutPlan(for: plan, workout: easyRun)
        let fake = FakeScheduler([
            .init(plan: workoutPlan, date: day(5), complete: false),
            .init(plan: workoutPlan, date: DateComponents(year: 2026, month: 10, day: 5, hour: 9), complete: true),
        ])

        try await makeBridge(fake).schedule(plan, workout: easyRun, calendar: calendar)

        let entries = await fake.entries
        #expect(entries.count == 1)
        #expect(entries[0].complete)
    }

    @Test("Two plans of the same workout on one day get separate entries")
    func scheduleKeepsPlansOfOneWorkoutApart() async throws {
        let fake = FakeScheduler()
        let bridge = makeBridge(fake)
        let morning = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let evening = PlannedActivity(workoutID: easyRun.id, date: date(5))

        try await bridge.schedule(morning, workout: easyRun, calendar: calendar)
        try await bridge.schedule(evening, workout: easyRun, calendar: calendar)
        await bridge.unschedule(morning)

        #expect(await fake.entries.map(\.plan.id) == [evening.id])
    }

    @Test("schedule leaves WorkoutKit untouched when the workout can't be mapped")
    func scheduleThrowsWithoutTouchingScheduler() async throws {
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let existing = try WorkoutKitBridge().workoutPlan(for: plan, workout: easyRun)
        let fake = FakeScheduler([.init(plan: existing, date: day(5), complete: false)])
        let bridge = WorkoutKitBridge(
            support: WorkoutKitSupportChecking(
                supportsActivity: { _ in false },
                supportsGoal: { _, _ in true },
                supportsAlert: { _, _ in true }
            ),
            scheduler: fake.scheduling
        )

        await #expect(throws: WorkoutKitMappingError.unsupportedActivity(.running)) {
            try await bridge.schedule(plan, workout: longRun, calendar: calendar)
        }
        #expect(await fake.entries.count == 1)
        #expect(await fake.removeCalls == 0)
    }

    // MARK: - unschedule

    @Test("unschedule removes the plan's entry whatever its day, and nothing else")
    func unscheduleRemovesOnlyThePlansEntry() async throws {
        let fake = FakeScheduler()
        let bridge = makeBridge(fake)
        let target = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let other = PlannedActivity(workoutID: easyRun.id, date: date(6))
        try await bridge.schedule(target, workout: easyRun, calendar: calendar)
        try await bridge.schedule(other, workout: easyRun, calendar: calendar)

        var moved = target
        moved.date = date(9) // the plan's date no longer matches its entry's
        await bridge.unschedule(moved)

        #expect(await fake.entries.map(\.plan.id) == [other.id])
    }

    @Test("unschedule is a no-op when nothing was scheduled for the plan")
    func unscheduleNoOpsForUnscheduledPlan() async {
        let fake = FakeScheduler()

        await makeBridge(fake).unschedule(PlannedActivity(workoutID: easyRun.id, date: date(5)))

        #expect(await fake.removeCalls == 0)
    }

    // MARK: - unscheduleAll(except:)

    @Test("unscheduleAll(except:) removes entries no plan id names, such as ones scheduled before MVP2-55")
    func unscheduleAllRemovesUnknownEntries() async throws {
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let known = try WorkoutKitBridge().workoutPlan(for: plan, workout: easyRun)
        let legacy = WorkoutPlan(.custom(try WorkoutKitBridge().customWorkout(from: easyRun)), id: UUID())
        let fake = FakeScheduler([
            .init(plan: known, date: day(5), complete: false),
            .init(plan: legacy, date: day(5), complete: false),
            .init(plan: legacy, date: day(6), complete: true),
        ])

        let removed = await makeBridge(fake).unscheduleAll(except: [plan.id])

        #expect(removed == 2)
        #expect(await fake.entries.map(\.plan.id) == [plan.id])
    }

    @Test("unscheduleAll(except:) with every entry's plan id removes nothing")
    func unscheduleAllKeepsKnownEntries() async throws {
        let plan = PlannedActivity(workoutID: easyRun.id, date: date(5))
        let known = try WorkoutKitBridge().workoutPlan(for: plan, workout: easyRun)
        let fake = FakeScheduler([.init(plan: known, date: day(5), complete: false)])

        let removed = await makeBridge(fake).unscheduleAll(except: [plan.id])

        #expect(removed == 0)
        #expect(await fake.removeCalls == 0)
    }
}
#endif
