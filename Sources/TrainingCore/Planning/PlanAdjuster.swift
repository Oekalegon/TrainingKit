import Foundation

/// The bounded adjust loop of the plan generator (MVP5-120): build a plan, evaluate it with
/// ``PlanEvaluator``, and while it has a ``Severity/risk``, try one adjustment and keep it only if the
/// risks become fewer, or stay as many but sit closer to their thresholds (the summed distance of
/// ``PlanFinding/value`` from ``PlanFinding/threshold`` shrinks).
///
/// Each step takes the first risk finding (chronologically) that still has an untried adjustment and
/// tries the gentlest one for its rule:
///
/// | Rule | Adjustments, in order |
/// |---|---|
/// | ``PlanRule/tsbBand``, ``PlanRule/strain`` | lower the volume of the micro, turn it into a down-week |
/// | ``PlanRule/longestRun`` | lower the volume of the micro, drop the session |
/// | ``PlanRule/hardSessionsPerMicro``, ``PlanRule/hardSessionSpacing``, ``PlanRule/monotony`` | ease the session, drop it (for `hardSessionsPerMicro` the last hard session of the micro) |
///
/// The volume step is a fixed factor (``volumeStep``) down to a floor (``minVolumeScale``). An
/// adjustment that is not kept still counts as tried, and a set of
/// levers is never built twice, so the loop cannot oscillate. It stops when the plan is acceptable,
/// when nothing untried is left, or after ``maxIterations`` adjustments, and then returns the plan
/// as it is, flagged not acceptable, with the findings. Warnings (race-day TSB, a high TSB, intensity
/// distribution) are kept in the result but never acted on. Pure: it reads no clock, and `today` is
/// passed to the provider.
public struct PlanAdjuster: Sendable {
    /// The races to check race-day TSB against.
    public var races: [Race]
    /// The paradigm whose rules apply, if any.
    public var paradigm: TrainingParadigm?
    /// The race the plan builds towards, if any.
    public var targetRace: Race?
    /// The thresholds to evaluate against.
    public var guardrails: PlanGuardrails
    /// The most adjustments the loop tries (kept or not) after the first plan.
    public var maxIterations: Int
    /// The factor one volume step multiplies a micro's volume by, between 0 and 1 (0.9 is 10 % less).
    public var volumeStep: Double
    /// The lowest volume factor a micro may be given; no step goes below it.
    public var minVolumeScale: Double

    /// Creates an adjuster.
    ///
    /// - Parameters:
    ///   - races: The races to check race-day TSB against; defaults to none.
    ///   - paradigm: The paradigm whose rules apply; defaults to `nil`.
    ///   - targetRace: The race the plan builds towards; defaults to `nil`.
    ///   - guardrails: The thresholds; defaults to ``PlanGuardrails``'s defaults.
    ///   - maxIterations: The most adjustments to try, at least 0; defaults to 8.
    ///   - volumeStep: The factor one volume step multiplies by, clamped to 0.01...0.99; defaults to 0.9.
    ///   - minVolumeScale: The lowest volume factor, clamped to 0.01...1; defaults to 0.5.
    public init(
        races: [Race] = [],
        paradigm: TrainingParadigm? = nil,
        targetRace: Race? = nil,
        guardrails: PlanGuardrails = PlanGuardrails(),
        maxIterations: Int = 8,
        volumeStep: Double = 0.9,
        minVolumeScale: Double = 0.5
    ) {
        self.races = races
        self.paradigm = paradigm
        self.targetRace = targetRace
        self.guardrails = guardrails
        self.maxIterations = max(0, maxIterations)
        self.volumeStep = min(max(volumeStep, 0.01), 0.99)
        self.minVolumeScale = min(max(minVolumeScale, 0.01), 1)
    }

    /// Builds the first plan and adjusts it until it has no risk or the bound is hit.
    ///
    /// - Parameters:
    ///   - provider: Builds the plan for a set of levers.
    ///   - today: The current day, passed to the provider and kept on the proposal.
    /// - Returns: The proposal: acceptable, or the plan as it stands with its risks and why the loop
    ///   stopped (``PlanProposal/outcome``).
    /// - Throws: Whatever `provider` throws.
    public func propose(using provider: some PlanCandidateProvider, today: Date) async throws -> PlanProposal {
        var levers = PlanLevers.none
        var candidate = try await provider.candidate(levers: levers, today: today)
        var evaluation = evaluate(candidate)
        var tried: Set<PlanLevers> = [levers]
        var history: [PlanIteration] = []
        var kept: [PlanCompromise] = []
        var outcome = PlanProposal.Outcome.acceptable

        while !evaluation.isAcceptable {
            if history.count >= maxIterations { outcome = .iterationLimit; break }
            guard let next = nextAdjustment(for: evaluation, candidate: candidate, levers: levers, tried: tried) else {
                outcome = .noAdjustmentLeft
                break
            }
            let trial = levers.applying(next.adjustment)
            tried.insert(trial)
            let trialCandidate = try await provider.candidate(levers: trial, today: today)
            let trialEvaluation = evaluate(trialCandidate)
            let before = risks(in: evaluation), after = risks(in: trialEvaluation)
            let keep = after < before || (after == before && excess(of: trialEvaluation) < excess(of: evaluation))
            history.append(PlanIteration(adjustment: next.adjustment, answering: next.rule, risksBefore: before, risksAfter: after, kept: keep))
            if keep {
                levers = trial
                candidate = trialCandidate
                evaluation = trialEvaluation
                kept.append(.adjusted(next.adjustment, answering: next.rule))
            }
        }

        return PlanProposal(
            candidate: candidate,
            evaluation: evaluation,
            compromises: candidate.compromises + kept,
            levers: levers,
            history: history,
            outcome: outcome,
            today: today,
            targetRaceID: targetRace?.id,
            calibrationWarning: paradigm?.calibrationWarning(for: targetRace)
        )
    }

    private func evaluate(_ candidate: PlanCandidate) -> PlanEvaluation {
        PlanEvaluator().evaluate(
            candidate.metrics,
            races: races,
            cycles: candidate.cycles,
            guardrails: guardrails,
            sessions: candidate.sessions,
            paradigm: paradigm,
            targetRace: targetRace
        )
    }

    private func risks(in evaluation: PlanEvaluation) -> Int {
        evaluation.findings.filter { $0.severity == .risk }.count
    }

    /// How far the risks are past their thresholds, summed: what lets a volume step that does not yet
    /// clear a risk still count as progress. The distances are in the units of their rules (TSB points,
    /// fractions, counts) and are added as they are, so a step that gains a lot on one risk can hide a
    /// small loss on another with the same number of risks; `risksAfter` and the history show it.
    private func excess(of evaluation: PlanEvaluation) -> Double {
        evaluation.findings.filter { $0.severity == .risk }.reduce(0) { $0 + abs($1.value - $1.threshold) }
    }

    /// The first untried adjustment for the earliest risk that has one.
    private func nextAdjustment(
        for evaluation: PlanEvaluation, candidate: PlanCandidate, levers: PlanLevers, tried: Set<PlanLevers>
    ) -> (adjustment: PlanAdjustment, rule: PlanRule)? {
        let micros = candidate.cycles.filter { $0.level == .micro }
        for finding in evaluation.findings where finding.severity == .risk {
            let micro = micros.first { $0.dateRange.contains(finding.day) }
            for adjustment in options(for: finding, micro: micro, sessions: candidate.sessions, levers: levers)
            where !tried.contains(levers.applying(adjustment)) {
                return (adjustment, finding.rule)
            }
        }
        return nil
    }

    private func options(for finding: PlanFinding, micro: TrainingCycle?, sessions: [PlanSession], levers: PlanLevers) -> [PlanAdjustment] {
        let microStart = micro?.dateRange.lowerBound
        var lower: [PlanAdjustment] = []
        var downWeek: [PlanAdjustment] = []
        if let microStart {
            let scale = levers.volumeScale(forMicro: microStart)
            if scale > minVolumeScale { lower = [.lowerVolume(microStart: microStart, scale: max(minVolumeScale, scale * volumeStep))] }
            if micro?.loadRole == .build || micro?.loadRole == nil { downWeek = [.downWeek(microStart: microStart)] }
        }
        // A finding of `hardSessionsPerMicro` is dated at the start of the micro, not at a session: it
        // takes the last hard session of the micro that is still planned.
        var day = finding.day
        if finding.rule == .hardSessionsPerMicro, let micro, let paradigm {
            let hard = sessions.filter {
                micro.dateRange.contains($0.day) && paradigm.isHard($0)
                    && !levers.easedDays.contains($0.day) && !levers.droppedDays.contains($0.day)
            }
            if let last = hard.map(\.day).max() { day = last }
        }
        let ease = [PlanAdjustment.easeSession(day: day)]
        let drop = [PlanAdjustment.dropSession(day: day)]
        switch finding.rule {
        case .tsbBand, .strain: return lower + downWeek
        case .longestRun: return lower + drop
        case .hardSessionsPerMicro, .hardSessionSpacing, .monotony: return ease + drop
        case .raceDayTSB, .intensityDistribution: return []
        }
    }
}
