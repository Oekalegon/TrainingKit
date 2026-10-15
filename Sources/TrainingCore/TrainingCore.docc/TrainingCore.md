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
- ``PaceSettings``
- ``HeartRateZoneModel``
- ``HeartRateZoneMethod``
- ``HeartRateZoneSettings``
- ``MaxHeartRateSource``
- ``PeakHeartRateDetector``
- ``MaxHeartRateSuggestion``
- ``LactateThresholdSource``
- ``FieldTestMeasurer``
- ``FieldTestResult``
- ``FieldTestError``
- ``TanakaHRMaxEstimator``

### Activity

- ``Activity``
- ``HeartRateSample``
- ``SpeedSample``
- ``ActivityStep``
- ``ElevationStats``
- ``CadenceStats``
- ``GeographicBounds``
- ``Sport``
- ``Venue``
- ``ActivitySource``

### Training Load

- ``TrainingLoad``
- ``LoadMethod``
- ``LoadError``
- ``TRIMPCoefficients``
- ``LoadCalculator``
- ``ExponentialTRIMPCalculator``
- ``DurationRPECalculator``
- ``ImportedLoadCalculator``

### Structured Workouts

- ``WorkoutTemplate``
- ``DistanceSystem``
- ``StructuredWorkout``
- ``WorkoutPurpose``
- ``WorkoutBlock``
- ``WorkoutStep``
- ``StepKind``
- ``StepGoal``
- ``IntensityTarget``

### Planning

- ``PlannedActivity``
- ``TrainingPlan``
- ``PlanStatus``
- ``PlanPreferences``
- ``RunAvailability``
- ``DaySlot``
- ``PlannedLoadEstimator``
- ``TRIMPPlanEstimator``
- ``LinkedActivityRefinedEstimator``
- ``PlanReconciler``
- ``ActivityStepAligner``
- ``WorkoutDurationEstimator``

### Fitness Series

- ``DayLoad``
- ``DailyLoadSeries``
- ``LoadModelParameters``
- ``FitnessMetrics``
- ``FitnessMetricsCalculator``

### Statistics

- ``ActivitySummary``
- ``ActivityListItem``
- ``TimeInZone``
- ``WeeklyStats``
- ``WeeklyDelta``
- ``SportWeekStats``
- ``PeriodStats``
- ``PeriodDelta``
- ``SportPeriodStats``
- ``StatisticsCalculator``
- ``WorkoutProjection``
- ``PaceHistory``

### Periodisation

- ``TrainingCycle``
- ``CycleLevel``
- ``CyclePhase``
- ``MicroLoadRole``
- ``Microcycle``
- ``MesocycleTemplate``
- ``MacroTemplate``
- ``CycleLayoutBuilder``
- ``Race``
- ``RacePriority``

### Goals

- ``Goal``
- ``GoalTarget``
- ``GoalMeasure``
- ``GoalPeriod``

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
- ``TrainingPlanStore``
- ``TrainingPlanError``
- ``WorkoutLibraryStore``
- ``CycleStore``
- ``CycleStoreError``
- ``CycleNestingValidator``
- ``RaceStore``
- ``GoalStore``
- ``GoalStoreError``
- ``WorkoutTemplateStore``
- ``WorkoutTemplateStoreError``
- ``TemplateRemoval``
- ``AthleteStore``
- ``InMemoryStore``
- ``StoreSet``
- ``ImportAnchor``
- ``ImportResult``
- ``ActivityImporting``

### Export

- ``CalendarExport``
- ``CalendarExportBuilder``
- ``CalendarImportPlanner``
- ``CalendarImportPlan``
- ``CalendarImportReport``
- ``CalendarImportError``

### Facade

- ``TrainingModel``
