import Foundation

/// A reusable, parameterized workout blueprint in the athlete's library, e.g. "Recovery run" with
/// a `duration` parameter, instantiated into a concrete ``StructuredWorkout`` when scheduled.
public struct WorkoutTemplate: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this template.
    public let id: UUID
    /// The template's display name.
    public var name: String
    /// The kind of activity this template is for.
    public var sport: Sport
    /// The parameters this template's blocks may reference. Keys must be unique within a
    /// template — a duplicate key silently resolves to whichever entry appears first.
    public var parameters: [WorkoutTemplateParameter]
    /// The ordered blocks making up this template.
    public var blocks: [TemplateBlock]

    /// Creates a workout template.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The template's display name.
    ///   - sport: The kind of activity this template is for.
    ///   - parameters: The parameters this template's blocks may reference.
    ///   - blocks: The ordered blocks making up this template.
    public init(
        id: UUID = UUID(),
        name: String,
        sport: Sport,
        parameters: [WorkoutTemplateParameter],
        blocks: [TemplateBlock]
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.parameters = parameters
        self.blocks = blocks
    }
}

extension WorkoutTemplate {
    /// Produces a concrete workout by resolving this template's parameters.
    ///
    /// - Parameters:
    ///   - name: The instantiated workout's display name; defaults to this template's name.
    ///   - values: Parameter key to value; a key declared in this template's `parameters` but
    ///     missing from `values` resolves to that parameter's `defaultValue`.
    /// - Returns: A ``StructuredWorkout`` with every ``TemplateValue`` resolved to a fixed value.
    /// - Throws: ``WorkoutTemplateError/undeclaredParameter(_:)`` if a step or block references a
    ///   `.parameter(_:)` key that isn't declared in this template's `parameters` — a typo or a
    ///   stale reference, never something `values` alone can fix.
    public func instantiate(name: String? = nil, values: [String: Double] = [:]) throws(WorkoutTemplateError) -> StructuredWorkout {
        func resolve(_ key: String) throws(WorkoutTemplateError) -> Double {
            if let value = values[key] {
                return value
            }
            guard let parameter = parameters.first(where: { $0.key == key }) else {
                throw .undeclaredParameter(key)
            }
            return parameter.defaultValue
        }

        var resolvedBlocks: [WorkoutBlock] = []
        resolvedBlocks.reserveCapacity(blocks.count)
        for block in blocks {
            var steps: [WorkoutStep] = []
            steps.reserveCapacity(block.steps.count)
            for step in block.steps {
                steps.append(WorkoutStep(kind: step.kind, goal: try step.goal.resolve(resolve), target: step.target))
            }
            resolvedBlocks.append(WorkoutBlock(steps: steps, repetitions: try block.repetitions.resolve(resolve)))
        }
        return StructuredWorkout(name: name ?? self.name, sport: sport, blocks: resolvedBlocks)
    }

    /// The estimated training load `instantiate(values:)` would produce, without building the
    /// intermediate `StructuredWorkout` by hand.
    ///
    /// - Parameters:
    ///   - values: Parameter key to value, as passed to `instantiate(values:)`.
    ///   - estimator: Estimates load from a step's target intensity in place of measured heart rate.
    ///   - athlete: Supplies the zone settings/sex/pace model `estimator` estimates against.
    /// - Returns: The estimated ``TrainingLoad`` for the instantiated workout.
    /// - Throws: Whatever `instantiate(name:values:)` throws.
    public func expectedLoad(
        values: [String: Double] = [:],
        estimator: PlannedLoadEstimator,
        athlete: AthleteProfile
    ) throws(WorkoutTemplateError) -> TrainingLoad {
        estimator.estimatedLoad(for: try instantiate(values: values), athlete: athlete)
    }
}

extension TemplateValue where Value == Double {
    fileprivate func resolve(_ resolve: (String) throws(WorkoutTemplateError) -> Double) throws(WorkoutTemplateError) -> Double {
        switch self {
        case .fixed(let value): value
        case .parameter(let key): try resolve(key)
        }
    }
}

extension TemplateValue where Value == Int {
    /// - Note: A resolved parameter value is rounded to the nearest integer rather than truncated,
    ///   so a fractional value from a non-integer-snapped input (e.g. a UI slider) doesn't silently
    ///   drop a whole repetition (`7.9` rounds to `8`, not `7`).
    fileprivate func resolve(_ resolve: (String) throws(WorkoutTemplateError) -> Double) throws(WorkoutTemplateError) -> Int {
        switch self {
        case .fixed(let value): value
        case .parameter(let key): Int(try resolve(key).rounded())
        }
    }
}

extension TemplateStepGoal {
    fileprivate func resolve(_ resolve: (String) throws(WorkoutTemplateError) -> Double) throws(WorkoutTemplateError) -> StepGoal {
        switch self {
        case .time(let value): .time(try value.resolve(resolve))
        case .distance(let value): .distance(try value.resolve(resolve))
        case .open: .open
        }
    }
}
