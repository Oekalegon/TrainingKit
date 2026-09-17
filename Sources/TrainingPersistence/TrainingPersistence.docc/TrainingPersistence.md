# ``TrainingPersistence``

SwiftData models and CloudKit sync that conform to TrainingCore's store protocols.

## Overview

`TrainingPersistence` depends on `TrainingCore` and is available on all supported platforms (iOS, watchOS, macOS). It is the shared source of truth that platform adapters and the macOS viewer/planner read from and write to.

## Topics

### Overview

- ``TrainingPersistence``

### Store

- ``SwiftDataStore``
- ``TrainingPersistenceContainer``

### Models

- ``ActivityRecord``
- ``PlannedActivityRecord``
- ``StructuredWorkoutRecord``
- ``TrainingCycleRecord``
- ``AthleteProfileRecord``
