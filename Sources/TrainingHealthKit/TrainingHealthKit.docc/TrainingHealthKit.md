# ``TrainingHealthKit``

Imports completed activities and heart-rate samples from HealthKit, plus resting heart rate and biological sex.

## Overview

`TrainingHealthKit` depends on `TrainingCore` and is available on iOS, watchOS, and macOS 14+. On macOS, HealthKit data only appears when the user has iCloud Health sync enabled — the Mac is otherwise a viewer/planner that receives data through `TrainingPersistence` and CloudKit rather than importing directly.

## Topics

### Overview

- ``TrainingHealthKit``

### Import

- ``HealthKitActivityImporter``
- ``HealthKitImportError``

### Athlete

- ``HealthKitAthleteReader``
- ``HealthKitAthleteSnapshot``

### Authorization

- ``HealthKitAuthorization``
