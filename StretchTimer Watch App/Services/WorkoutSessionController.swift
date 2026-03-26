import Foundation
import HealthKit

@MainActor
final class WorkoutSessionController: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStopping = false

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isAuthorizedForBackgroundSession: Bool {
        healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func requestAuthorizationIfNeeded() async throws {
        guard isAvailable else {
            throw WorkoutSessionError.unavailable
        }
        guard !isAuthorizedForBackgroundSession else { return }

        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        try await healthStore.requestAuthorization(toShare: shareTypes, read: [])
    }

    func startIfAvailable() {
        guard isAvailable, isAuthorizedForBackgroundSession, session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .flexibility
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder
            isStopping = false

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }
        } catch {
            self.session = nil
            self.builder = nil
        }
    }

    func stop() {
        guard let session else { return }
        guard !isStopping else { return }

        isStopping = true
        session.stopActivity(with: Date())
    }

    private func finishStopping(at endDate: Date) {
        guard let builder, let session else {
            reset()
            return
        }

        builder.endCollection(withEnd: endDate) { [weak self] _, _ in
            guard let self else { return }
            builder.discardWorkout()
            session.end()
            Task { @MainActor in
                self.reset()
            }
        }
    }

    private func reset() {
        session = nil
        builder = nil
        isStopping = false
    }
}

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .stopped else { return }
        Task { @MainActor in
            self.finishStopping(at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.reset()
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}

enum WorkoutSessionError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit workout sessions are not available on this device."
        case .authorizationDenied:
            return "Workout permission is required to keep the session active in the background."
        }
    }
}
