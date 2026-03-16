import Foundation

@MainActor
final class WorkoutSessionController {
    let isAvailable: Bool = false

    func startIfAvailable() {
        // HealthKit-backed background mode is not available in this build.
    }

    func stop() {
        // No-op for this build.
    }
}
