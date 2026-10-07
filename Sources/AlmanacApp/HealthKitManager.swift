import Foundation
import HealthKit
import AlmanacCore

@MainActor
final class HealthKitManager: NSObject, ObservableObject {
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isExerciseActive: Bool = false
    @Published var currentHeartRate: Int?
    @Published var activeWorkoutType: String?
    @Published var permissionDenied: Bool = false

    private let healthStore = HKHealthStore()
    private var workoutQuery: HKQuery?
    private var heartRateQuery: HKQuery?

    override init() {
        super.init()
        checkAuthorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.permissionDenied = true
            }
            return false
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate) ?? HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            checkAuthorizationStatus()
            startMonitoringExercise()
            return true
        } catch {
            DispatchQueue.main.async {
                self.permissionDenied = true
            }
            return false
        }
    }

    func checkAuthorizationStatus() {
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)

        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        if status == .sharingAuthorized {
            startMonitoringExercise()
        }
    }

    private func startMonitoringExercise() {
        queryCurrentWorkout()
        queryHeartRate()
    }

    private func queryCurrentWorkout() {
        let workoutType = HKObjectType.workoutType()

        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictEndDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, _ in
            guard let self = self else { return }

            let workouts = samples as? [HKWorkout] ?? []

            DispatchQueue.main.async {
                if let latestWorkout = workouts.first {
                    let timeSinceEnd = Date().timeIntervalSince(latestWorkout.endDate)
                    let isRecent = timeSinceEnd < 3600

                    self.isExerciseActive = isRecent
                    if isRecent {
                        self.activeWorkoutType = self.workoutTypeName(latestWorkout.workoutActivityType)
                    } else {
                        self.activeWorkoutType = nil
                    }
                } else {
                    self.isExerciseActive = false
                    self.activeWorkoutType = nil
                }
            }
        }

        healthStore.execute(query)
        self.workoutQuery = query
    }

    private func queryHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .minute, value: -5, to: now),
            end: now,
            options: .strictEndDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, _ in
            guard let self = self else { return }

            let heartRateSamples = samples as? [HKQuantitySample] ?? []

            DispatchQueue.main.async {
                if let latestSample = heartRateSamples.first {
                    let heartRateValue = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    self.currentHeartRate = Int(heartRateValue)
                } else {
                    self.currentHeartRate = nil
                }
            }
        }

        healthStore.execute(query)
        self.heartRateQuery = query
    }

    func refreshExerciseData() {
        queryCurrentWorkout()
        queryHeartRate()
    }

    private func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "Running"
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .walking:
            return "Walking"
        case .hiking:
            return "Hiking"
        case .yoga:
            return "Yoga"
        case .volleyball:
            return "Volleyball"
        case .basketball:
            return "Basketball"
        case .tennis:
            return "Tennis"
        case .soccer:
            return "Soccer"
        case .americanFootball:
            return "Football"
        case .baseball:
            return "Baseball"
        case .softball:
            return "Softball"
        case .rugby:
            return "Rugby"
        case .golf:
            return "Golf"
        case .cricket:
            return "Cricket"
        case .crossTraining:
            return "Cross Training"
        case .elliptical:
            return "Elliptical"
        case .stairClimbing:
            return "Stair Climbing"
        case .rowing:
            return "Rowing"
        case .boxing:
            return "Boxing"
        case .martialArts:
            return "Martial Arts"
        case .dance:
            return "Dance"
        case .kickboxing:
            return "Kickboxing"
        case .functionalStrengthTraining:
            return "Strength Training"
        case .cardioDance:
            return "Cardio Dance"
        case .handCycling:
            return "Hand Cycling"
        default:
            return "Exercise"
        }
    }
}
