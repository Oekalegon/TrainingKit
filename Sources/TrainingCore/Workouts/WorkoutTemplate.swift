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
    /// The parameters this template's blocks may reference.
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
    ///   - values: Parameter key to value; a key missing from `values` (or from this template's
    ///     `parameters`) resolves to `0`.
    /// - Returns: A ``StructuredWorkout`` with every ``TemplateValue`` resolved to a fixed value.
    public func instantiate(name: String? = nil, values: [String: Double] = [:]) -> StructuredWorkout {
        func resolve(_ key: String) -> Double {
            values[key] ?? parameters.first { $0.key == key }?.defaultValue ?? 0
        }

        let resolvedBlocks = blocks.map { block in
            WorkoutBlock(
                steps: block.steps.map { step in
                    WorkoutStep(kind: step.kind, goal: step.goal.resolve(resolve), target: step.target)
                },
                repetitions: block.repetitions.resolve(resolve)
            )
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
    public func expectedLoad(
        values: [String: Double] = [:],
        estimator: PlannedLoadEstimator,
        athlete: AthleteProfile
    ) -> TrainingLoad {
        estimator.estimatedLoad(for: instantiate(values: values), athlete: athlete)
    }
}

extension TemplateValue where Value == Double {
    fileprivate func resolve(_ resolve: (String) -> Double) -> Double {
        switch self {
        case .fixed(let value): value
        case .parameter(let key): resolve(key)
        }
    }
}

extension TemplateValue where Value == Int {
    fileprivate func resolve(_ resolve: (String) -> Double) -> Int {
        switch self {
        case .fixed(let value): value
        case .parameter(let key): Int(resolve(key))
        }
    }
}

extension TemplateStepGoal {
    fileprivate func resolve(_ resolve: (String) -> Double) -> StepGoal {
        switch self {
        case .time(let value): .time(value.resolve(resolve))
        case .distance(let value): .distance(value.resolve(resolve))
        case .open: .open
        }
    }
}
