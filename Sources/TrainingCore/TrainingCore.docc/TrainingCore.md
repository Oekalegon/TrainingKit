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
- ``RecoveryDays``
- ``DistanceSystem``
- ``StructuredWorkout``
- ``WorkoutPurpose``
- ``WorkoutBlock``
- ``WorkoutStep``
- ``StepKind``
- ``TemplateAnalysis``
- ``StepGoal``
- ``IntensityTarget``

### Planning

- ``PlannedActivity``
- ``TrainingPlan``
- ``PlanStatus``
- ``PlanPreferences``
- ``VolumeTarget``
- ``VolumeCurveBuilder``
- ``MicroVolumeTarget``
- ``VolumeCurveError``
- ``LeadTimeCompromiser``
- ``LeadTimeAdjustment``
- ``LeadTimeCompromise``
- ``LeadTimeError``
- ``TemplateFitter``
- ``TemplateFit``
- ``TemplateChoice``
- ``StepTargetResolver``
- ``StepTargetResolution``
- ``UnresolvedStep``
- ``UnresolvedReason``
- ``PlanAdjuster``
- ``PlanProposal``
- ``PlanIteration``
- ``PlanAdjustment``
- ``PlanLevers``
- ``PlanCompromise``
- ``CalibrationWarning``
- ``PlanCandidate``
- ``PlanCandidateProvider``
- ``PlanGenerator``
- ``PlanRequest``
- ``PlanGeneratorError``
- ``PlanPreview``
- ``PlanProposalError``
- ``DayAssigner``
- ``DayAssignment``
- ``DayAssignmentResult``
- ``DroppedSession``
- ``DropReason``
- ``VolumeMeasure``
- ``RunAvailability``
- ``RunType``
- ``SessionType``
- ``DaySlot``
- ``SlotOptions``
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
- ``KeyRaceLayout``
- ``KeyRaceMicrocycles``
- ``KeyRaceCycles``
- ``KeyRaceAdjustment``
- ``Race``
- ``RaceError``
- ``RacePriority``
- ``SpecificPhaseTarget``
- ``SpecificPhaseTargetError``

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

### Training Paradigms

- ``TrainingParadigm``
- ``PlanGuardrails/Overrides``
- ``IntensityMix``
- ``RaceDistanceClass``
- ``PlanSession``
- ``SessionProfile``
- ``SpeedLevel``

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
