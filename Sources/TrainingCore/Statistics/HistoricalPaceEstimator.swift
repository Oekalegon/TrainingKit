import Foundation

/// Forecasts each step of a planned workout from the athlete's earlier workouts that resemble it
/// (MVP2-35, MVP2-111), for ``PlannedWorkoutProjector`` when it's given a non-empty
/// ``PaceHistory``.
///
/// 1. **Match.** Every earlier activity of the same sport family is scored on how closely its time
///    in each heart-rate zone matches the planned workout's, how close its duration is, how recent
///    it is, and whether it ran the same workout or a workout from the same template. The best
///    ``maximumMatches`` are kept; an activity whose zone mix overlaps less than
///    ``minimumZoneOverlap`` isn't similar at all.
/// 2. **Pace per zone.** The matches' time and distance in each zone give a pace per zone, pulled
///    towards ``AthleteProfile/paceModel``'s pace by ``priorSeconds`` of pretend evidence so a few
///    seconds in a zone can't swing it, and kept slower in lower zones than in higher ones: zone 1
///    is never faster than zone 4. The model's paces are first scaled by how much faster or slower
///    the matches were overall, so zones the matches didn't reach move along with those they did.
/// 3. **Pace per step.** For matches linked to a plan, each step was laid over the recording (see
///    ``PaceHistory``). A planned step takes the pace earlier steps of the same kind and zone were
///    run at, favouring steps of similar length (a 400 m rep is run faster than a 2 km one), pulled
///    towards the zone's pace the same way. This keeps a zone-2 recovery jog between intervals, run
///    while the heart rate is still coming down, from being forecast at steady zone-2 pace.
/// 4. **Open steps.** An `.open` step (the run to the hill in hill sprints) takes the median time
///    the same step took in earlier runs of the same workout or, failing that, of workouts made
///    from the same template (whose blocks and steps sit in the same places whatever their
///    parameter values).
///
/// A `.time` step's distance and a `.distance` step's time then follow from its pace. Without any
/// match or open-step evidence there's nothing to forecast from, and the projector keeps the pace
/// model's figures.
struct HistoricalPaceEstimator: Sendable {
    /// Turns step goals into durations at the pace model; also supplies the default `.open` step
    /// duration.
    var durationEstimator: WorkoutDurationEstimator
    /// Seconds of evidence the prior pace counts as; more observed time than this outweighs it.
    var priorSeconds: Double = 300
    /// After this many days an activity counts half as much as one on the cutoff day.
    var recencyHalfLifeDays: Double = 60
    /// How many similar activities are used.
    var maximumMatches = 12
    /// The least share of time-in-zone an activity must have in common with the planned workout.
    var minimumZoneOverlap = 0.5

    /// The forecast for every step of a workout.
    struct Forecast: Sendable {
        let steps: [PlannedWorkoutProjector.StepProjection]
        /// How many earlier activities the paces were learned from.
        let matchedActivityCount: Int
    }

    /// One planned step with what the pace model says about it.
    private struct PlannedStep {
        let expanded: PaceHistory.ExpandedStep
        /// The step's zone as the projector reports it (0 below zone 1).
        let zone: Int
        /// The zone its pace is looked up at: `zone`, at least 1.
        let paceZone: Int
        /// The pace model's speed for this step (m/s). A `.distance` step's comes from
        /// ``WorkoutDurationEstimator``, as the projector's always has.
        let priorSpeed: Double
        /// The step's duration at `priorSpeed`, for weighing the zone mix and step lengths.
        let priorSeconds: Double
    }

    private typealias Match = (observation: PaceHistory.Observation, weight: Double)

    /// The forecast for each step of `workout`, or `nil` when `history` has nothing to say about it
    /// (no similar earlier activity and no earlier run of its open steps), the athlete has no
    /// zone settings, or the zone method can't resolve every zone.
    ///
    /// - Parameters:
    ///   - workout: The planned workout.
    ///   - athlete: Supplies current zone settings and the prior pace model.
    ///   - history: Earlier activities.
    ///   - cutoff: Only activities that started before this are used, so a planned day's own
    ///     activity (or a later one) can't inform its own forecast.
    ///   - excludedActivityID: An activity to leave out, e.g. the one the plan is linked to.
    func forecast(
        for workout: StructuredWorkout, athlete: AthleteProfile, history: PaceHistory,
        before cutoff: Date, excluding excludedActivityID: UUID?
    ) -> Forecast? {
        guard let settings = athlete.currentHeartRateZoneSettings else { return nil }
        let zoneModel = HeartRateZoneModel(settings: settings)
        guard let boundaries = TimeInZoneBuilder.zoneBoundaries(zoneModel) else { return nil }
        let zonePriors = Dictionary(uniqueKeysWithValues: (1...5).map {
            ($0, 1 / athlete.paceModel.secondsPerMeter(atZone: $0))
        })

        let planned = PaceHistory.expandedSteps(of: workout).map { expanded -> PlannedStep in
            let step = expanded.step
            let zone = TimeInZoneBuilder.zone(for: zoneModel.intensityRatio(for: step.target), boundaries: boundaries)
            let paceZone = max(zone, 1)
            let zonePrior = zonePriors[paceZone] ?? 1
            let priorSpeed: Double
            let priorSeconds: Double
            switch step.goal {
            case .distance(let meters):
                priorSeconds = durationEstimator.duration(for: step, athlete: athlete)
                priorSpeed = priorSeconds > 0 ? meters / priorSeconds : zonePrior
            case .time, .open:
                priorSeconds = durationEstimator.duration(for: step, athlete: athlete)
                priorSpeed = zonePrior
            }
            return PlannedStep(expanded: expanded, zone: zone, paceZone: paceZone, priorSpeed: priorSpeed, priorSeconds: priorSeconds)
        }

        let candidates = history.observations.filter {
            $0.start < cutoff && $0.activityID != excludedActivityID && $0.sport.isSameFamily(as: workout.sport)
        }
        let matches = self.matches(for: workout, planned: planned, among: candidates, asOf: cutoff)
        let openDurations = self.openStepDurations(for: workout, among: candidates)
        guard !matches.isEmpty || !openDurations.isEmpty else { return nil }

        let zoneSpeeds = self.zoneSpeeds(matches: matches, zonePriors: zonePriors)
        let steps = planned.map { plannedStep -> PlannedWorkoutProjector.StepProjection in
            let zonePrior = zonePriors[plannedStep.paceZone] ?? 1
            // The step's own prior relative to its zone (a distance step whose pace the duration
            // estimator took from another zone keeps that offset), moved with the zone's learned pace.
            let target = (zoneSpeeds[plannedStep.paceZone] ?? zonePrior) * plannedStep.priorSpeed / zonePrior
            let speed = stepSpeed(for: plannedStep, matches: matches, target: target)
            let step = plannedStep.expanded.step
            let duration: TimeInterval
            let distance: Double
            switch step.goal {
            case .time(let seconds):
                duration = seconds
                distance = seconds * speed
            case .distance(let meters):
                duration = meters / speed
                distance = meters
            case .open:
                duration = openDurations[plannedStep.expanded.position] ?? plannedStep.priorSeconds
                distance = duration * speed
            }
            return PlannedWorkoutProjector.StepProjection(
                block: plannedStep.expanded.position.block, repetition: plannedStep.expanded.repetition,
                step: step, duration: duration, zone: plannedStep.zone, distanceMeters: distance
            )
        }
        return Forecast(steps: steps, matchedActivityCount: matches.count)
    }

    // MARK: - Matching

    /// The most similar candidates with their weights, best first.
    private func matches(
        for workout: StructuredWorkout, planned: [PlannedStep],
        among candidates: [PaceHistory.Observation], asOf date: Date
    ) -> [Match] {
        let plannedTotal = planned.reduce(0) { $0 + $1.priorSeconds }
        guard plannedTotal > 0 else { return [] }
        var plannedShare: [Int: Double] = [:]
        for step in planned {
            plannedShare[step.paceZone, default: 0] += step.priorSeconds / plannedTotal
        }

        let scored = candidates.compactMap { observation -> Match? in
            let total = observation.zoneSeconds
            guard total > 0 else { return nil }
            let overlap = (1...5).reduce(0.0) { sum, zone in
                sum + min(plannedShare[zone] ?? 0, (observation.zones[zone]?.seconds ?? 0) / total)
            }
            guard overlap >= minimumZoneOverlap else { return nil }
            let durationSimilarity = Self.similarity(plannedTotal, observation.duration)
            let ageDays = max(0, date.timeIntervalSince(observation.start) / 86_400)
            let recency = pow(0.5, ageDays / recencyHalfLifeDays)
            let structure: Double
            if observation.workoutID == workout.id {
                structure = 3
            } else if let templateID = workout.templateID, observation.templateID == templateID {
                structure = 2
            } else {
                structure = 1
            }
            return (observation, overlap * overlap * durationSimilarity * recency * structure)
        }
        return Array(scored.sorted { $0.weight > $1.weight }.prefix(maximumMatches))
    }

    /// `min / max` of two positive amounts: 1 when equal, towards 0 as they diverge.
    static func similarity(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return 0 }
        return min(a, b) / max(a, b)
    }

    // MARK: - Paces

    /// Speed (m/s) per zone 1...5 from the matches, shrunk towards the scaled prior and made to rise
    /// with the zone; the priors unchanged when there are no matches.
    private func zoneSpeeds(matches: [Match], zonePriors: [Int: Double]) -> [Int: Double] {
        guard !matches.isEmpty else { return zonePriors }
        var evidence: [Int: PaceHistory.Sample] = [:]
        for zone in 1...5 {
            for (observation, weight) in matches {
                guard let sample = observation.zones[zone] else { continue }
                evidence[zone, default: PaceHistory.Sample()] += PaceHistory.Sample(
                    seconds: sample.seconds * weight, meters: sample.meters * weight
                )
            }
        }

        // How much faster (or slower) than the pace model the athlete ran overall, itself pulled
        // towards 1 by `priorSeconds` at an average prior pace. It scales every zone's prior, so a
        // zone with no evidence of its own follows the zones that have it: an athlete 20 % faster
        // than the model at zone 4 is likely faster at zone 5 too, and an unscaled zone-5 prior
        // would otherwise drag zone 4 back down when the zones are made to rise.
        let averagePrior = (1...5).reduce(0.0) { $0 + (zonePriors[$1] ?? 1) } / 5
        let observedMeters = evidence.values.reduce(0.0) { $0 + $1.meters }
        let expectedMeters = evidence.reduce(0.0) { $0 + $1.value.seconds * (zonePriors[$1.key] ?? 1) }
        let scale = (observedMeters + priorSeconds * averagePrior) / (expectedMeters + priorSeconds * averagePrior)

        var speeds: [Double] = []
        var weights: [Double] = []
        for zone in 1...5 {
            let zoneEvidence = evidence[zone] ?? PaceHistory.Sample()
            let prior = (zonePriors[zone] ?? 1) * scale
            speeds.append((zoneEvidence.meters + priorSeconds * prior) / (zoneEvidence.seconds + priorSeconds))
            weights.append(zoneEvidence.seconds + priorSeconds)
        }
        let rising = Self.nonDecreasing(speeds, weights: weights)
        return Dictionary(uniqueKeysWithValues: rising.enumerated().map { ($0.offset + 1, $0.element) })
    }

    /// Speed (m/s) for one planned step: earlier steps of the same kind and zone, weighted by their
    /// activity's match weight and by how close their length is, shrunk towards `target`.
    private func stepSpeed(for planned: PlannedStep, matches: [Match], target: Double) -> Double {
        var evidence = PaceHistory.Sample()
        for (observation, weight) in matches {
            for step in observation.steps where step.kind == planned.expanded.step.kind && step.zone == planned.paceZone {
                guard step.sample.seconds > 0 else { continue }
                let lengthSimilarity: Double
                if case .distance(let meters) = planned.expanded.step.goal {
                    lengthSimilarity = Self.similarity(meters, step.sample.meters)
                } else {
                    lengthSimilarity = Self.similarity(planned.priorSeconds, step.sample.seconds)
                }
                let stepWeight = weight * lengthSimilarity
                evidence += PaceHistory.Sample(seconds: step.sample.seconds * stepWeight, meters: step.sample.meters * stepWeight)
            }
        }
        guard evidence.seconds > 0 else { return target }
        let speed = (evidence.meters + priorSeconds * target) / (evidence.seconds + priorSeconds)
        return speed > 0 ? speed : target
    }

    /// The median observed duration of each `.open` step of `workout`, from earlier runs of the same
    /// workout or, failing that, of workouts made from the same template.
    private func openStepDurations(
        for workout: StructuredWorkout, among candidates: [PaceHistory.Observation]
    ) -> [PaceHistory.StepPosition: Double] {
        guard workout.blocks.contains(where: { block in block.steps.contains { $0.goal == .open } }) else { return [:] }
        let sameWorkout = candidates.filter { $0.workoutID == workout.id }
        let sameTemplate = workout.templateID.map { templateID in
            candidates.filter { $0.templateID == templateID }
        } ?? []
        let source = sameWorkout.contains { $0.steps.contains(where: \.isOpen) } ? sameWorkout : sameTemplate

        var observed: [PaceHistory.StepPosition: [Double]] = [:]
        for observation in source {
            for step in observation.steps where step.isOpen {
                observed[step.position, default: []].append(step.sample.seconds)
            }
        }
        return observed.compactMapValues(Self.median)
    }

    /// The median of `values`, averaging the middle two of an even count; `nil` when empty.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The weighted least-squares non-decreasing fit to `values` (pool adjacent violators): wherever
    /// a lower zone came out faster than a higher one, both get their weighted average.
    static func nonDecreasing(_ values: [Double], weights: [Double]) -> [Double] {
        var blocks: [(value: Double, weight: Double, count: Int)] = []
        for (value, weight) in zip(values, weights) {
            blocks.append((value, weight, 1))
            while blocks.count > 1, blocks[blocks.count - 2].value > blocks[blocks.count - 1].value {
                let upper = blocks.removeLast()
                let lower = blocks.removeLast()
                let weight = lower.weight + upper.weight
                let value = weight > 0 ? (lower.value * lower.weight + upper.value * upper.weight) / weight : lower.value
                blocks.append((value, weight, lower.count + upper.count))
            }
        }
        return blocks.flatMap { Array(repeating: $0.value, count: $0.count) }
    }
}
