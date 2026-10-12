import Foundation

/// Lays the steps the Watch recorded (``Activity/steps``) over the steps of the plan's workout
/// (MVP2-146), so each planned step has what the athlete did in it next to it.
///
/// The Watch numbers a step `block.repetition.step`, all from 0. Block 0 is the warm-up, the plan's
/// blocks follow, and the cool-down is last: for a workout whose first block is a single warm-up step
/// and whose last is a single cool-down step (the shape `WorkoutKitBridge` sends to the Watch), the
/// Watch's block number is simply the workout's own block index. A workout without a warm-up has
/// been seen only on paper, so both numberings are tried (the blocks starting at 0 or at 1) and the
/// one in which every recorded step lands on a planned step wins; if both do and they disagree (a
/// partial recording can fit either), there is no alignment, so a step is never shown against the
/// wrong planned one. When neither fits, but the counts agree, the steps are paired in order;
/// otherwise there is no alignment.
public enum ActivityStepAligner {
    /// The recorded step for each of `workout`'s steps, in the order they are performed with block
    /// repetitions expanded (the order of ``CalendarExport/Step``).
    ///
    /// - Parameters:
    ///   - steps: The activity's recorded steps, ``Activity/steps``.
    ///   - workout: The workout of the plan the activity was started from.
    /// - Returns: One element per planned step: the recorded step, or `nil` for a planned step the
    ///   athlete skipped. `nil` as a whole when `steps` is empty or cannot be laid over `workout`
    ///   (the plan was edited after the workout, or the counts and numbers disagree).
    public static func align(_ steps: [ActivityStep], with workout: StructuredWorkout) -> [ActivityStep?]? {
        guard !steps.isEmpty else { return nil }
        let planned = PaceHistory.expandedSteps(of: workout)
        guard !planned.isEmpty else { return nil }
        let ordered = steps.sorted { $0.start < $1.start }

        let fits = [0, 1].compactMap { alignByKeyPath(ordered, planned: planned, blockOffset: $0) }
        if fits.count == 1 { return fits[0] }
        // Both numberings fit, which a partial recording of a workout with no warm-up can do (the
        // athlete stopped after the first step, and its key path reads as another planned step in the
        // other numbering): no guess, unless they agree anyway.
        if fits.count == 2 { return fits[0] == fits[1] ? fits[0] : nil }
        // The key paths didn't fit but each planned step has exactly one recorded step.
        if ordered.count == planned.count { return ordered }
        return nil
    }

    /// Matches by the Watch's numbering, with the workout's block index plus `blockOffset` as the
    /// Watch's block number; `nil` unless every recorded step finds a distinct planned step.
    private static func alignByKeyPath(
        _ steps: [ActivityStep], planned: [PaceHistory.ExpandedStep], blockOffset: Int
    ) -> [ActivityStep?]? {
        struct Key: Hashable { let block: Int; let repetition: Int; let step: Int }
        var byKey: [Key: ActivityStep] = [:]
        for step in steps {
            let key = Key(block: step.block, repetition: step.repetition, step: step.step)
            guard byKey.updateValue(step, forKey: key) == nil else { return nil }
        }
        var aligned: [ActivityStep?] = []
        var used = 0
        for plannedStep in planned {
            let key = Key(
                block: plannedStep.position.block + blockOffset, repetition: plannedStep.repetition - 1,
                step: plannedStep.position.step
            )
            let match = byKey[key]
            if match != nil { used += 1 }
            aligned.append(match)
        }
        return used == steps.count ? aligned : nil
    }
}
