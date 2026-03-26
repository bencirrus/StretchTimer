import Foundation

enum SharedSessionStore {
    static let appGroupIdentifier = "group.net.TheCorp.StretchTimer"
    static let widgetKind = "net.TheCorp.StretchTimer.session"

    private enum Key {
        static let isSessionActive = "shared.isSessionActive"
        static let sessionEndDate = "shared.sessionEndDate"
        static let currentPhase = "shared.currentPhase"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func updateSession(isActive: Bool, phase: TimerPhase, sessionEndDate: Date?) {
        guard let defaults else { return }

        defaults.set(isActive, forKey: Key.isSessionActive)
        defaults.set(phase.rawValue, forKey: Key.currentPhase)
        defaults.set(sessionEndDate, forKey: Key.sessionEndDate)
    }

    static func clearSession() {
        guard let defaults else { return }

        defaults.set(false, forKey: Key.isSessionActive)
        defaults.removeObject(forKey: Key.sessionEndDate)
        defaults.removeObject(forKey: Key.currentPhase)
    }
}
