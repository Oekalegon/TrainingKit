# TrainingKit

A Swift package for iOS 17+, watchOS 10+, and macOS 14+: import completed training activities,
compute training load, plan structured workouts and training cycles, and project a continuous
fitness series (CTL/ATL/TSB/monotony/strain) with injury-risk and progress guardrails.

Library only, no UI — companion iOS and Mac apps live in their own repositories and consume this
package as a remote Swift Package dependency.

## Package layout

| Target | Depends on | Platforms | Purpose |
|---|---|---|---|
| `TrainingCore` | Foundation only | all | Models, load calculators, series engine, estimators, store protocols |
| `TrainingHealthKit` | Core, HealthKit | iOS, watchOS, macOS 14+ | Activity + HR sample import, resting HR, biological sex |
| `TrainingWorkoutKit` | Core, WorkoutKit | iOS, watchOS | Structured workout ↔ `CustomWorkout`, schedule sync |
| `TrainingPersistence` | Core, SwiftData | all | SwiftData models + CloudKit sync, conforms to Core store protocols |
| `TrainingTools` | Core | all | Provider-neutral tool registry, JSON schemas, `PlanSandbox` |
| `TrainingToolsAnthropic` | Tools | all | Messages API tool-use loop |
| `TrainingToolsFoundationModels` | Tools, FoundationModels | iOS/macOS 26+ | On-device model adapter |

`TrainingFIT` (FIT/TCX import and export for Garmin/COROS) is planned for a later milestone.

See `docs/design/trainingKit-design.md` for the full MVP 1 design, including the fitness series
engine, plan evaluation guardrails, and periodisation model.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching strategy and CI requirements.
