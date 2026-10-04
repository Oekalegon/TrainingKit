import Foundation

/// How ``WorkoutTemplate/defaultTitle(values:distanceSystem:)`` writes a distance.
public enum DistanceSystem: Sendable, Hashable {
    /// Meters below 1 km, kilometers above: "400 m", "23 km".
    case metric
    /// Miles: "13.1 mi".
    case imperial
}

extension WorkoutTemplate {
    /// A short title describing this template at the given parameter values, e.g. "50min Easy Run",
    /// "23 km Long Run" or "10x8sec Hill Sprints".
    ///
    /// The title is derived from the instantiated workout's structure, not from a per-template
    /// rule, so a new template gets a sensible title without changes here:
    /// - A block repeated more than once is an interval set: "reps x work", where the work is the
    ///   first `.work` step's time or distance ("8x60sec", "8x400 m").
    /// - Otherwise it is the longest `.work` step among the single-repetition blocks, so a warmup
    ///   and cooldown never count ("50min", "23 km"). The longest, not the first, because a
    ///   template may open with a short `.work` ramp-in ahead of its main effort.
    /// - A workout with neither (all steps open-ended) is just the name.
    ///
    /// The name is ``titleName`` if set, otherwise ``name`` with each word capitalized.
    ///
    /// - Parameters:
    ///   - values: Parameter key to value, as passed to ``instantiate(name:values:)``.
    ///   - distanceSystem: How distances are written; durations are always "h", "min" and "sec".
    /// - Returns: The title; the name alone if the template has no work step with a goal, or if a
    ///   block references an undeclared parameter.
    public func defaultTitle(values: [String: Double] = [:], distanceSystem: DistanceSystem = .metric) -> String {
        let label = Self.titleCased(titleName ?? name)
        guard let workout = try? instantiate(values: values) else { return label }

        if let set = workout.blocks.first(where: { $0.repetitions > 1 }),
           let work = set.steps.first(where: { $0.kind == .work }),
           let effort = Self.describe(work.goal, distanceSystem: distanceSystem) {
            return "\(set.repetitions)x\(effort) \(label)"
        }

        let main = workout.blocks
            .filter { $0.repetitions == 1 }
            .flatMap(\.steps)
            .filter { $0.kind == .work }
            .max { Self.magnitude($0.goal) < Self.magnitude($1.goal) }
        if let main, let amount = Self.describe(main.goal, distanceSystem: distanceSystem) {
            return "\(amount) \(label)"
        }
        return label
    }

    /// A step goal's size for picking the longest: seconds for a time, meters for a distance. The
    /// two aren't comparable, but one template doesn't mix them in its main steps.
    private static func magnitude(_ goal: StepGoal) -> Double {
        switch goal {
        case .time(let seconds): seconds
        case .distance(let meters): meters
        case .open: 0
        }
    }

    private static func describe(_ goal: StepGoal, distanceSystem: DistanceSystem) -> String? {
        switch goal {
        case .time(let seconds): duration(seconds)
        case .distance(let meters): distance(meters, in: distanceSystem)
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

    /// "400 m", "1.5 km", "23 km", "13.1 mi": one decimal at most, dropped when it is zero.
    private static func distance(_ meters: Double, in system: DistanceSystem) -> String {
        func trimmed(_ value: Double) -> String {
            let rounded = (value * 10).rounded() / 10
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        switch system {
        case .metric:
            return meters < 1000 ? "\(Int(meters.rounded())) m" : "\(trimmed(meters / 1000)) km"
        case .imperial:
            return "\(trimmed(meters / 1609.344)) mi"
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
