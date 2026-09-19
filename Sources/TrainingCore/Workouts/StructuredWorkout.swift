import Foundation

/// A reusable structured workout in the athlete's library, e.g. "6x400m intervals".
public struct StructuredWorkout: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this workout.
    public let id: UUID
    /// The workout's display name.
    public var name: String
    /// The kind of activity this workout is for.
    public var sport: Sport
    /// The ordered blocks making up this workout.
    public var blocks: [WorkoutBlock]
    /// Identity of the synced WorkoutKit plan; `nil` if this workout hasn't been synced yet.
    public var workoutKitID: UUID?
    /// The ``WorkoutTemplate`` this workout was instantiated from, or `nil` for one built by hand or
    /// created before this field existed. Together with ``parameterValues`` it's what lets an app
    /// re-open the template's parameters and instantiate an edited copy (MVP2-41).
    public var templateID: UUID?
    /// The resolved value of every parameter the template declares, as used to build ``blocks`` —
    /// `nil` exactly when ``templateID`` is. Stored rather than re-derived from `blocks`, since
    /// several parameters can collapse into the same step values.
    public var parameterValues: [String: Double]?

    /// Creates a structured workout.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The workout's display name.
    ///   - sport: The kind of activity this workout is for.
    ///   - blocks: The ordered blocks making up this workout.
    ///   - workoutKitID: Identity of the synced WorkoutKit plan, if already synced.
    ///   - templateID: The template this workout was instantiated from, if any.
    ///   - parameterValues: The resolved parameter values it was instantiated with, if any.
    public init(
        id: UUID = UUID(),
        name: String,
        sport: Sport,
        blocks: [WorkoutBlock],
        workoutKitID: UUID? = nil,
        templateID: UUID? = nil,
        parameterValues: [String: Double]? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.blocks = blocks
        self.workoutKitID = workoutKitID
        self.templateID = templateID
        self.parameterValues = parameterValues
    }
}
