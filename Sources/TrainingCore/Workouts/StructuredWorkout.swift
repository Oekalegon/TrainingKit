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

    /// Creates a structured workout.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The workout's display name.
    ///   - sport: The kind of activity this workout is for.
    ///   - blocks: The ordered blocks making up this workout.
    ///   - workoutKitID: Identity of the synced WorkoutKit plan, if already synced.
    public init(
        id: UUID = UUID(),
        name: String,
        sport: Sport,
        blocks: [WorkoutBlock],
        workoutKitID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.blocks = blocks
        self.workoutKitID = workoutKitID
    }
}
