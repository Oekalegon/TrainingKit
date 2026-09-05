# ``TrainingWorkoutKit``

Bridges TrainingKit's structured workout model to Apple WorkoutKit and syncs schedules.

## Overview

`TrainingWorkoutKit` depends on `TrainingCore` and is available on iOS and watchOS. WorkoutKit does not exist on macOS, so this target is a no-op there; the Mac app talks to `TrainingPersistence` and CloudKit instead of syncing plans directly.

## Topics

### Overview

- ``TrainingWorkoutKit``
