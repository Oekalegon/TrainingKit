# ``TrainingCore``

Platform-independent models, training-load calculators, and the fitness series engine at the heart of TrainingKit.

## Overview

`TrainingCore` depends only on Foundation, so the training-load math, periodisation model, and daily fitness series engine can be tested and reused on any platform. It defines the athlete profile, completed activities, structured workouts, training cycles, and the store protocols that platform adapters (`TrainingHealthKit`, `TrainingWorkoutKit`, `TrainingPersistence`) conform to.

See `docs/design/trainingKit-design.md` in the package repository for the full model design.

## Topics

### Overview

- ``TrainingCore``

### Athlete

- ``AthleteProfile``
- ``BiologicalSex``
- ``Weekday``
- ``PaceModel``
- ``HeartRateZoneModel``
- ``HeartRateZoneMethod``
- ``HeartRateZoneSettings``
- ``TanakaHRMaxEstimator``

### Activity

- ``Activity``
- ``HeartRateSample``
- ``SpeedSample``
- ``ElevationStats``
- ``CadenceStats``
- ``GeographicBounds``
- ``Sport``
- ``ActivitySource``

### Training Load

- ``TrainingLoad``
- ``LoadMethod``
- ``LoadError``
- ``TRIMPCoefficients``
- ``LoadCalculator``
- ``ExponentialTRIMPCalculator``
- ``DurationRPECalculator``

### Structured Workouts

- ``StructuredWorkout``
- ``WorkoutBlock``
- ``WorkoutStep``
- ``StepKind``
- ``StepGoal``
- ``IntensityTarget``

### Planning

- ``PlannedActivity``
- ``PlannedLoadEstimator``
- ``TRIMPPlanEstimator``
- ``PlanReconciler``
- ``WorkoutDurationEstimator``

### Fitness Series

- ``DayLoad``
- ``DailyLoadSeries``
- ``LoadModelParameters``
- ``FitnessMetrics``
- ``FitnessMetricsCalculator``

### Statistics

- ``ActivitySummary``
- ``TimeInZone``
- ``WeeklyStats``
- ``WeeklyDelta``
- ``SportWeekStats``
- ``PeriodStats``
- ``PeriodDelta``
- ``SportPeriodStats``
- ``StatisticsCalculator``

### Periodisation

- ``TrainingCycle``
- ``CycleLevel``
- ``CyclePhase``
- ``Microcycle``
- ``MesocycleTemplate``
- ``MacroTemplate``
- ``CycleLayoutBuilder``
- ``Race``
- ``RacePriority``

### Plan Evaluation

- ``PlanEvaluator``
- ``PlanEvaluation``
- ``PlanFinding``
- ``PlanRule``
- ``PlanGuardrails``
- ``Severity``

### Stores

- ``ActivityStore``
- ``PlanStore``
- ``WorkoutLibraryStore``
- ``CycleStore``
- ``CycleStoreError``
- ``AthleteStore``
- ``InMemoryStore``
- ``StoreSet``
- ``ImportAnchor``
- ``ImportResult``
- ``ActivityImporting``

### Facade

- ``TrainingModel``
