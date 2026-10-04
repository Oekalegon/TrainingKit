import Foundation

extension WorkoutTemplate {
    /// A short title describing this template at the given parameter values, e.g. "50min Easy Run",
    /// "23 km Long Run" or "10x8sec Hill Sprints".
    ///
    /// The title is derived from the instantiated workout's structure, not from a per-template
    /// rule, so a new template gets a sensible title without changes here:
    /// - A block repeated more than once is an interval set: "reps x work", where the work is the
    ///   first `.work` step's time or distance ("8x60sec", "8x400 m").
    /// - Otherwise, if a `.work` step is a distance, the longest such distance ("23 km"). Warmup
    ///   and cooldown are left out: they are timed, and a time can't be added to a distance.
    /// - Otherwise the workout's total time, every timed step counted, warmup and cooldown
    ///   included ("40min" for an easy run whose main step is 30 minutes between two 5-minute
    ///   steps), so the title says how long the session takes, not just its main block.
    /// - A workout with none of these (all steps open-ended) is just the name.
    ///
    /// The name is ``titleName`` if set, otherwise ``name`` with each word capitalized.
    ///
    /// - Parameters:
    ///   - values: Parameter key to value, as passed to ``instantiate(name:values:)``.
    ///   - distanceSystem: How distances are written; durations are always "h", "min" and "sec".
    /// - Returns: The title; the name alone if the template has no usable goal (all open-ended, or
    ///   a time or distance that is negative or not finite), or if a block references an undeclared
    ///   parameter. For that last case, ``instantiate(name:values:)`` throws the actual error; a
    ///   display string deliberately doesn't.
    public func defaultTitle(values: [String: Double] = [:], distanceSystem: DistanceSystem = .metric) -> String {
        let label = Self.titleCased(titleName ?? name)
        guard let workout = try? instantiate(values: values) else { return label }

        // An interval set decides the title even when its effort is unusable: falling through to the
        // longest single step would title "8 x NaN" intervals after their warmup ramp-in.
        if let set = workout.blocks.first(where: { $0.repetitions > 1 }) {
            guard let work = set.steps.first(where: { $0.kind == .work }),
                  let effort = Self.describe(work.goal, distanceSystem: distanceSystem) else { return label }
            return "\(set.repetitions)x\(effort) \(label)"
        }

        let steps = workout.blocks.flatMap(\.steps)
        let distances = steps.filter { $0.kind == .work }.compactMap { step -> Double? in
            if case .distance(let meters) = step.goal { meters } else { nil }
        }
        if !distances.isEmpty {
            guard let longest = distances.filter({ $0.isFinite && $0 > 0 }).max() else { return label }
            return "\(Self.distance(longest, in: distanceSystem)) \(label)"
        }

        let times = steps.compactMap { step -> TimeInterval? in
            if case .time(let seconds) = step.goal { seconds } else { nil }
        }
        // One bad time makes the total meaningless, so it isn't skipped.
        guard times.allSatisfy({ $0.isFinite && $0 >= 0 }), times.reduce(0, +) > 0 else { return label }
        return "\(Self.duration(times.reduce(0, +))) \(label)"
    }

    private static func describe(_ goal: StepGoal, distanceSystem: DistanceSystem) -> String? {
        switch goal {
        case .time(let seconds): seconds.isFinite && seconds > 0 ? duration(seconds) : nil
        case .distance(let meters): meters.isFinite && meters > 0 ? distance(meters, in: distanceSystem) : nil
        case .open: nil
        }
    }

    /// "8sec", "90sec", "2min", "50min", "1h30min". Under two minutes and not a whole minute is
    /// written in seconds ("90sec"); anything longer in whole hours and minutes, with leftover
    /// seconds dropped, since a title doesn't need that precision.
    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 120, total % 60 != 0 { return "\(total)sec" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)min" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)min"
    }

    /// "400 m", "1.5 km", "23 km" (metric); "440 yd", "13.1 mi" (imperial). Kilometers and miles
    /// have one decimal at most, dropped when it is zero; yards are rounded to the nearest 10,
    /// since an effort of 54.7 yd reads as "50 yd". The unit is chosen after rounding, so 999.6 m
    /// is "1 km" and not "1000 m".
    private static func distance(_ meters: Double, in system: DistanceSystem) -> String {
        func trimmed(_ value: Double) -> String {
            let rounded = (value * 10).rounded() / 10
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        switch system {
        case .metric:
            let rounded = meters.rounded()
            return rounded < 1000 ? "\(Int(rounded)) m" : "\(trimmed(meters / 1000)) km"
        case .imperial:
            let miles = meters / 1609.344
            if miles < 0.5 {
                return "\(max(10, Int((meters / 0.9144 / 10).rounded()) * 10)) yd"
            }
            return "\(trimmed(miles)) mi"
        }
    }

    /// Capitalizes the first letter of each word, leaving the rest as written ("Easy run" becomes
    /// "Easy Run", "(track)" becomes "(Track)", "Full-out" stays as it is).
    private static func titleCased(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                guard let index = word.firstIndex(where: \.isLetter) else { return String(word) }
                return word[..<index] + word[index].uppercased() + word[word.index(after: index)...]
            }
            .joined(separator: " ")
    }
}
