import Foundation

/// A reusable structured workout in the athlete's library, e.g. "6x400m intervals".
public struct StructuredWorkout: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var sport: Sport
    public var blocks: [WorkoutBlock]
    /// Identity of the synced WorkoutKit plan; `nil` if this workout hasn't been synced yet.
    public var workoutKitID: UUID?

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
