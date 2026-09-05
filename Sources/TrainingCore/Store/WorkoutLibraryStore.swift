import Foundation

/// Storage contract for the athlete's library of structured workouts.
public protocol WorkoutLibraryStore: Sendable {
    /// Every workout in the library.
    func workouts() async throws -> [StructuredWorkout]

    /// The workout with this id, if any.
    func workout(id: UUID) async throws -> StructuredWorkout?

    /// Inserts new workouts or replaces existing ones matched by `id`.
    func upsert(_ workouts: [StructuredWorkout]) async throws

    /// Removes the workout with this id, if any.
    func deleteWorkout(id: UUID) async throws
}
