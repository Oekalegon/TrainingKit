import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("Plan preview and commit", .serialized)
struct PlanCommitTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel(withPlanStore: Bool = true) -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store,
            trainingPlanStore: withPlanStore ? store : nil
        )
        return (store, TrainingModel(stores: stores, athlete: AthleteProfile.fixture()))
    }

    private func workout(_ name: String = "Steady") -> StructuredWorkout {
        StructuredWorkout(
            name: name, sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(3))])]
        )
    }

    /// A proposal with a macro, two planned workouts, and the given findings.
    private func proposal(findings: [PlanFinding] = [], workouts: [StructuredWorkout]? = nil, plannedWorkoutID: UUID? = nil) -> PlanProposal {
        let w = workout("Proposed")
        let macro = TrainingCycle(level: .macro, phase: .base, name: "Macro", dateRange: day(0)...day(13))
        let id = plannedWorkoutID ?? w.id
        let candidate = PlanCandidate(
            cycles: [macro],
            plannedActivities: [PlannedActivity(workoutID: id, date: day(1)), PlannedActivity(workoutID: id, date: day(3))],
            workouts: workouts ?? [w],
            sessions: [],
            metrics: []
        )
        return PlanProposal(
            candidate: candidate, evaluation: PlanEvaluation(findings: findings),
            compromises: [.overriddenPreference(.maxWeeklyVolume)], levers: .none, outcome: findings.isEmpty ? .acceptable : .noAdjustmentLeft,
            today: day(0)
        )
    }

    private let risk = PlanFinding(day: Date(timeIntervalSince1970: 1_700_000_000), rule: .tsbBand, severity: .risk, value: -40, threshold: -30)
    private let warning = PlanFinding(day: Date(timeIntervalSince1970: 1_700_000_000), rule: .raceDayTSB, severity: .warning, value: 40, threshold: 25)

    private func addActivePlan(_ model: TrainingModel, store: InMemoryStore, followed: Bool) async throws -> TrainingPlan {
        let old = try await model.createTrainingPlan(named: "Old", status: .active, asOf: day(0))
        let w = workout("Old workout")
        try await store.upsert([w])
        try await store.upsert([
            PlannedActivity(workoutID: w.id, date: day(-5), completedActivityID: followed ? UUID() : nil, planID: old.id),
            PlannedActivity(workoutID: w.id, date: day(2), planID: old.id),
            PlannedActivity(workoutID: w.id, date: day(1), planID: old.id),
            PlannedActivity(workoutID: w.id, date: day(4), completedActivityID: UUID(), planID: old.id),
        ])
        return old
    }

    @Test("a candidate saved before it had workouts decodes with none")
    func legacyCandidateDecodes() throws {
        let candidate = PlanCandidate(cycles: [], plannedActivities: [], workouts: [workout()], sessions: [], metrics: [])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as! [String: Any]
        json.removeValue(forKey: "workouts")
        let decoded = try JSONDecoder().decode(PlanCandidate.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.workouts.isEmpty)
    }

    @Test("a preview with no active plan replaces nothing and shows the proposal's views")
    func previewWithoutActivePlan() async throws {
        let (_, model) = makeModel()
        let preview = try await model.preview(proposal(findings: [risk, warning]), asOf: day(0))
        #expect(preview.replacedPlan == nil)
        #expect(preview.replacedActivities.isEmpty)
        #expect(!preview.replacedPlanIsFollowed)
        #expect(preview.risks == [risk])
        #expect(preview.warnings == [warning])
        #expect(!preview.isAcceptable)
        #expect(preview.compromises == [.overriddenPreference(.maxWeeklyVolume)])
        #expect(preview.cycles.count == 1)
        #expect(preview.plannedActivities.count == 2)
        #expect(preview.workouts.count == 1)
    }

    @Test("a preview lists the active plan's upcoming uncompleted workouts in date order")
    func previewListsReplaced() async throws {
        let (store, model) = makeModel()
        let old = try await addActivePlan(model, store: store, followed: true)
        let preview = try await model.preview(proposal(), asOf: day(0))
        #expect(preview.replacedPlan?.id == old.id)
        #expect(preview.replacedActivities.map(\.date) == [day(1), day(2)])
        #expect(preview.replacedPlanIsFollowed)
    }

    @Test("a preview of an unfollowed plan says it will not be cancelled")
    func previewUnfollowed() async throws {
        let (store, model) = makeModel()
        _ = try await addActivePlan(model, store: store, followed: false)
        // The completed workout on day 4 still makes it followed; remove that signal for this case.
        let all = try await store.plans(in: Date.distantPast...Date.distantFuture)
        for plan in all where plan.completedActivityID != nil { try await store.deletePlan(id: plan.id) }
        let preview = try await model.preview(proposal(), asOf: day(0))
        #expect(!preview.replacedPlanIsFollowed)
    }

    @Test("committing saves a draft with stamped cycles and workouts and leaves the active plan alone")
    func commitDraft() async throws {
        let (store, model) = makeModel()
        let old = try await addActivePlan(model, store: store, followed: false)
        let seen = proposal()
        let plan = try await model.commit(seen, named: "Marathon", asOf: day(0))
        #expect(plan.status == .draft)
        #expect(plan.name == "Marathon")
        #expect(model.activeTrainingPlan?.id == old.id)
        #expect(model.trainingPlans.contains { $0.id == plan.id })
        let cycles = try await model.cycles(ofPlan: plan.id, in: day(-30)...day(30))
        #expect(cycles.map(\.id) == seen.candidate.cycles.map(\.id))
        #expect(plan.macroCycleID == cycles.first?.id)
        let stored = try await model.plannedActivities(ofPlan: plan.id, in: day(-30)...day(30))
        #expect(stored.map(\.date).sorted() == [day(1), day(3)])
        #expect(try await store.workout(id: seen.candidate.workouts[0].id) != nil)
        #expect(!model.plans.contains { $0.planID == plan.id })
    }

    @Test("activating cancels a followed plan with a date and demotes an unfollowed one")
    func commitActivate() async throws {
        let (store, model) = makeModel()
        let followedPlan = try await addActivePlan(model, store: store, followed: true)
        let first = try await model.commit(proposal(), named: "New", activate: true, asOf: day(5))
        #expect(model.activeTrainingPlan?.id == first.id)
        #expect(first.status == .active)
        #expect(model.trainingPlans.first { $0.id == followedPlan.id }?.status == .cancelled)
        #expect(model.trainingPlans.first { $0.id == followedPlan.id }?.cancelledDate != nil)
        #expect(try await model.plannedActivities(ofPlan: followedPlan.id, in: day(-30)...day(30)).count == 4)

        let second = try await model.commit(proposal(), named: "Newer", activate: true, asOf: day(6))
        #expect(model.activeTrainingPlan?.id == second.id)
        #expect(model.trainingPlans.first { $0.id == first.id }?.status == .draft)
    }

    @Test("activating a proposal with risks needs acceptingRisks; a draft does not")
    func risksBlockActivation() async throws {
        let (store, model) = makeModel()
        let risky = proposal(findings: [risk, warning])
        await #expect(throws: PlanProposalError.hasRisks([risk])) {
            try await model.commit(risky, named: "Risky", activate: true, asOf: day(0))
        }
        #expect(model.trainingPlans.isEmpty)
        #expect(try await store.trainingPlans().isEmpty)
        #expect(try await store.workouts().isEmpty)

        let draft = try await model.commit(risky, named: "Risky draft", asOf: day(0))
        #expect(draft.status == .draft)
        let active = try await model.commit(risky, named: "Accepted", activate: true, acceptingRisks: true, asOf: day(0))
        #expect(model.activeTrainingPlan?.id == active.id)
    }

    @Test("warnings alone never block activation")
    func warningsDoNotBlock() async throws {
        let (_, model) = makeModel()
        let plan = try await model.commit(proposal(findings: [warning]), named: "Warned", activate: true, asOf: day(0))
        #expect(plan.status == .active)
    }

    @Test("planned workouts without a workout are refused and nothing is written")
    func missingWorkouts() async throws {
        let (store, model) = makeModel()
        let lost = UUID()
        await #expect(throws: PlanProposalError.missingWorkouts([lost])) {
            try await model.commit(proposal(workouts: [], plannedWorkoutID: lost), named: "Broken", asOf: day(0))
        }
        #expect(try await store.trainingPlans().isEmpty)
    }

    @Test("workouts already in the library satisfy the planned workouts")
    func libraryWorkouts() async throws {
        let (store, model) = makeModel()
        let w = workout("Library")
        try await store.upsert([w])
        let plan = try await model.commit(proposal(workouts: [], plannedWorkoutID: w.id), named: "From library", asOf: day(0))
        #expect(try await model.plannedActivities(ofPlan: plan.id, in: day(-30)...day(30)).count == 2)
    }

    @Test("without a plan store committing throws notConfigured")
    func notConfigured() async throws {
        let (_, model) = makeModel(withPlanStore: false)
        await #expect(throws: TrainingPlanError.notConfigured) {
            try await model.commit(proposal(), named: "X", asOf: day(0))
        }
    }
}
