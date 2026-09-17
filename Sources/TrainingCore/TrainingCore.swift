/// Pure Foundation models, load calculators, the fitness series engine, and store protocols.
///
/// `TrainingCore` never imports an Apple platform framework, so the training-load math stays
/// testable on any platform. See `trainingKit — Package Design (MVP 1)` for the full model.
///
/// - Note: This type's name is also this module's name. That's harmless on its own, but if a
///   downstream adapter also defines a type with the same (unqualified) name as one of
///   `TrainingCore`'s own types — as `TrainingWorkoutKit`'s `WorkoutStep` does, colliding with
///   ``WorkoutStep`` here — writing `TrainingCore.WorkoutStep` to disambiguate doesn't work: the
///   bare identifier `TrainingCore` resolves to *this enum*, not the module, so the compiler looks
///   for a nested `WorkoutStep` inside it and fails. The fix used in `TrainingWorkoutKit` is a
///   scoped import — `import struct TrainingCore.WorkoutStep` — which binds the bare name
///   unambiguously to Core's type in that file. Reach for the same pattern for any future
///   same-named collision (e.g. a `TrainingFIT` adapter).
public enum TrainingCore {}
