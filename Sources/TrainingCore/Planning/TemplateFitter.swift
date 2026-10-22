import Foundation

/// Picks the library template, and the parameter values, that best meet a ``SessionProfile``
/// (MVP5-118). Pure and deterministic: the same inputs give the same result.
///
/// 1. **Hard filter.** A template takes part when it is running, not archived, tagged with the
///    profile's ``SessionProfile/sessionType`` (an untagged template never matches), and, when the
///    profile asks for them, its ``TemplateAnalysis/workLength`` and ``TemplateAnalysis/workCount``
///    overlap the profile's ranges. Athlete templates take part like built-in ones.
/// 2. **Closest fit.** Each remaining template gets the parameter values that bring it nearest the
///    profile: the work-length parameters (those of hard work steps) are set so each hard step
///    lasts the work length asked for, then the duration parameters of the easy work steps (when
///    there are any) or else the repetitions are chosen so the session's duration is nearest the
///    target. Parameters that are neither (a recovery, say) stay at their default. Repetitions are
///    limited to those that keep the work count in the profile's range. Templates rank by the
///    relative duration error, then by name, then by id; this is a lexicographic rule, not a weighted score.
/// 3. **Rotation.** If the best template was used last micro (`previous`), the best one that was not
///    takes its place when its error is at most ``rotationTolerance`` (10 percentage points) worse.
///
/// A work-length parameter is solved on the duration of the one step that uses it, so a template with
/// several (mixed intervals) sets each of them to the work length asked for, within its own range.
public enum TemplateFitter {
    /// How much worse (as a fraction of the target duration) a template may fit than the best one
    /// and still replace it when the best was used in the previous micro.
    public static let rotationTolerance = 0.1

    /// Fits a template to a profile.
    ///
    /// - Parameters:
    ///   - profile: What the phase asks of the session.
    ///   - targetSeconds: The duration the session should have, in seconds, from the micro's volume;
    ///     should be positive.
    ///   - templates: The templates to choose from, the athlete's own as well as the built-in ones.
    ///   - previous: The ids of the templates used in the previous micro, for rotation; defaults to none.
    ///   - workLength: The work length to aim for, in seconds, normally
    ///     ``SessionProfile/progressedWorkLength(microIndex:of:)``; defaults to `nil`, which uses the
    ///     middle of the profile's ``SessionProfile/workLength`` (or the parameter defaults when it has none).
    ///   - athlete: Supplies the pace model that times distance steps.
    /// - Returns: The best ``TemplateFit``, or ``TemplateFit/missingTemplate(_:)`` when no template passes the filter.
    public static func fit(
        profile: SessionProfile,
        targetSeconds: TimeInterval,
        templates: [WorkoutTemplate],
        previous: [UUID] = [],
        workLength: TimeInterval? = nil,
        athlete: AthleteProfile
    ) -> TemplateFit {
        let aim = workLength ?? profile.workLength.map { ($0.lowerBound + $0.upperBound) / 2 }
        let candidates: [TemplateChoice] = templates.compactMap { template in
            guard template.sport == .running, !template.isArchived, template.sessionType == profile.sessionType,
                  let analysis = try? template.analysis(athlete: athlete),
                  accepts(profile, analysis) else { return nil }
            return choice(for: template, analysis: analysis, profile: profile, target: targetSeconds, workLength: aim, athlete: athlete)
        }.sorted { lhs, rhs in
            if abs(lhs.error - rhs.error) > 1e-9 { return lhs.error < rhs.error }
            if lhs.template.name != rhs.template.name { return lhs.template.name < rhs.template.name }
            return lhs.template.id.uuidString < rhs.template.id.uuidString
        }
        guard let best = candidates.first else { return .missingTemplate(profile) }
        if previous.contains(best.template.id),
           let other = candidates.first(where: { !previous.contains($0.template.id) && $0.error <= best.error + rotationTolerance }) {
            return .fit(other)
        }
        return .fit(best)
    }

    private static func accepts(_ profile: SessionProfile, _ analysis: TemplateAnalysis) -> Bool {
        if let wanted = profile.workLength {
            guard let reachable = analysis.workLength, reachable.overlaps(wanted) else { return false }
        }
        if let wanted = profile.workCount, !analysis.workCount.overlaps(wanted) { return false }
        return true
    }

    private static func choice(
        for template: WorkoutTemplate, analysis: TemplateAnalysis, profile: SessionProfile,
        target: TimeInterval, workLength: TimeInterval?, athlete: AthleteProfile
    ) -> TemplateChoice? {
        let estimator = WorkoutDurationEstimator()
        func range(_ parameter: WorkoutTemplateParameter) -> ClosedRange<Double> {
            parameter.range ?? parameter.defaultValue...parameter.defaultValue
        }
        func key<Value>(_ value: TemplateValue<Value>) -> String? {
            if case .parameter(let key) = value { key } else { nil }
        }
        // The parameters of each role, from the steps that reference them.
        var workKeys: [String: TemplateStep] = [:]
        var volumeKeys: [String] = []
        var repetitionKeys: [String] = []
        for block in template.blocks {
            if let repetitionKey = key(block.repetitions) { repetitionKeys.append(repetitionKey) }
            for step in block.steps where step.kind == .work {
                let goalKey: String? = switch step.goal {
                case .time(let value): key(value)
                case .distance(let value): key(value)
                case .open: nil
                }
                guard let goalKey else { continue }
                if step.isHardWork(in: block) { workKeys[goalKey] = step } else { volumeKeys.append(goalKey) }
            }
        }
        volumeKeys.removeAll { workKeys[$0] != nil }
        let parameters = Dictionary(uniqueKeysWithValues: template.parameters.map { ($0.key, $0) })

        var base = Dictionary(uniqueKeysWithValues: template.parameters.map { ($0.key, $0.defaultValue) })
        // The work length: solve each hard step's duration for its parameter.
        if let workLength {
            for (key, step) in workKeys {
                guard let parameter = parameters[key] else { continue }
                if case .time = step.goal {
                    base[key] = min(max(workLength, range(parameter).lowerBound), range(parameter).upperBound)
                    continue
                }
                func seconds(_ x: Double) -> TimeInterval {
                    estimator.duration(for: WorkoutStep(kind: .work, goal: .distance(x), target: step.target), athlete: athlete)
                }
                base[key] = solve(range(parameter), toward: workLength, using: seconds)
            }
        }

        func measure(_ values: [String: Double]) -> (seconds: TimeInterval, count: Int)? {
            guard let workout = try? template.instantiate(values: values) else { return nil }
            let seconds = estimator.duration(for: workout, athlete: athlete)
            let count = zip(workout.blocks, template.blocks).reduce(0) { total, pair in
                total + pair.0.repetitions * pair.0.steps.filter { $0.isHardWork(in: pair.1) }.count
            }
            return (seconds, count)
        }

        // Candidate repetitions: every whole number in the range of the repetition parameters.
        let repetitionRanges = repetitionKeys.compactMap { parameters[$0].map(range) }
        let lower = repetitionRanges.map { Int($0.lowerBound.rounded(.up)) }.min()
        let upper = repetitionRanges.map { Int($0.upperBound.rounded(.down)) }.max()
        let repetitions: [Int?] = if let lower, let upper, lower <= upper { Array(lower...min(upper, lower + 999)) } else { [nil] }
        let defaultRepetitions = repetitionKeys.first.flatMap { parameters[$0]?.defaultValue }.map { Int($0.rounded()) }

        var best: (values: [String: Double], seconds: TimeInterval, error: Double, distance: Int)?
        for n in repetitions {
            var values = base
            if let n {
                for key in repetitionKeys {
                    if let parameter = parameters[key] { values[key] = min(max(Double(n), range(parameter).lowerBound), range(parameter).upperBound) }
                }
            }
            if !volumeKeys.isEmpty {
                func seconds(_ t: Double) -> TimeInterval {
                    var trial = values
                    for key in volumeKeys {
                        if let parameter = parameters[key] { trial[key] = range(parameter).lowerBound + (range(parameter).upperBound - range(parameter).lowerBound) * t }
                    }
                    return measure(trial)?.seconds ?? .infinity
                }
                let t = solve(0...1, toward: target, using: seconds)
                for key in volumeKeys {
                    if let parameter = parameters[key] { values[key] = range(parameter).lowerBound + (range(parameter).upperBound - range(parameter).lowerBound) * t }
                }
            }
            guard let measured = measure(values) else { continue }
            if let wanted = profile.workCount, !wanted.contains(measured.count) { continue }
            let error = abs(measured.seconds - target) / max(target, 1)
            let distance = n.flatMap { n in defaultRepetitions.map { abs(n - $0) } } ?? 0
            if let current = best {
                let better = error < current.error - 1e-9 || (abs(error - current.error) <= 1e-9 && distance < current.distance)
                if !better { continue }
            }
            best = (values, measured.seconds, error, distance)
        }
        guard let best else { return nil }
        return TemplateChoice(template: template, values: best.values, seconds: best.seconds, error: best.error, analysis: analysis)
    }

    /// The value in `range` at which the non-decreasing `function` is nearest `goal`, by bisection.
    private static func solve(_ range: ClosedRange<Double>, toward goal: Double, using function: (Double) -> Double) -> Double {
        if function(range.lowerBound) >= goal { return range.lowerBound }
        if function(range.upperBound) <= goal { return range.upperBound }
        var (low, high) = (range.lowerBound, range.upperBound)
        for _ in 0..<50 {
            let middle = (low + high) / 2
            if function(middle) < goal { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
}
