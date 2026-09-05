import TrainingCore

#if canImport(WorkoutKit)
import WorkoutKit
#endif

/// Bridges `StructuredWorkout` (Core) to Apple WorkoutKit's `CustomWorkout`, and syncs schedules.
///
/// WorkoutKit does not exist on macOS, so this target is a no-op there; the Mac app talks to
/// `TrainingPersistence` + CloudKit instead of syncing plans directly.
public enum TrainingWorkoutKit {}
