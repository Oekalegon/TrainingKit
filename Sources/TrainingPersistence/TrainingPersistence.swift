import SwiftData
import TrainingCore

/// SwiftData models that conform to Core's store protocols, in two stores: plans, workouts, cycles,
/// races and the athlete's preferences sync through CloudKit; everything derived from HealthKit stays
/// on the device (MVP2-131).
public enum TrainingPersistence {}
