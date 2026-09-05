# ``TrainingCore``

Platform-independent models, training-load calculators, and the fitness series engine at the heart of TrainingKit.

## Overview

`TrainingCore` depends only on Foundation, so the training-load math, periodisation model, and daily fitness series engine can be tested and reused on any platform. It defines the athlete profile, completed activities, structured workouts, training cycles, and the store protocols that platform adapters (`TrainingHealthKit`, `TrainingWorkoutKit`, `TrainingPersistence`) conform to.

See `docs/design/trainingKit-design.md` in the package repository for the full model design.

## Topics

### Overview

- ``TrainingCore``
