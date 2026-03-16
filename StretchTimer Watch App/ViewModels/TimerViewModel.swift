import Combine
import Foundation
import SwiftUI
import WatchKit

@MainActor
final class TimerViewModel: ObservableObject {
    @Published var holdSeconds: Int
    @Published var shiftSeconds: Int
    @Published var announcementsEnabled: Bool
    @Published var totalDurationSeconds: Int
    @Published var sessionVolume: Float

    @Published private(set) var isRunning = false
    @Published private(set) var currentPhase: TimerPhase = .hold
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var totalRemainingSeconds: Int
    @Published private(set) var backgroundModeChoice: BackgroundModeChoice?
    private(set) var isDisplayDimmed = false

    private let announcementService: AnnouncementService
    private let workoutSessionController: WorkoutSessionController
    private let notificationScheduler: NotificationScheduler
    private let extendedRuntimeController: ExtendedRuntimeSessionController
    private let audioCuePlayer: AudioCuePlayer
    private var ticker: AnyCancellable?
    private var phaseEndDate: Date?
    private var totalEndDate: Date?
    private var lastCountdownSecond: Int?
    private var lastCuePhase: TimerPhase?

    private enum Key {
        static let holdSeconds = "settings.holdSeconds"
        static let shiftSeconds = "settings.shiftSeconds"
        static let announcementsEnabled = "settings.announcementsEnabled"
        static let backgroundModeChoice = "settings.backgroundModeChoice"
        static let totalDurationSeconds = "settings.totalDurationSeconds"
        static let sessionVolume = "settings.sessionVolume"
    }

    static let minTotalSeconds = 120
    static let maxTotalSeconds = 900
    static let totalStepSeconds = 30
    static let defaultTotalSeconds = 390
    static let defaultSessionVolume: Float = 1.0

    init(
        announcementService: AnnouncementService,
        workoutSessionController: WorkoutSessionController,
        notificationScheduler: NotificationScheduler,
        extendedRuntimeController: ExtendedRuntimeSessionController,
        audioCuePlayer: AudioCuePlayer
    ) {
        self.announcementService = announcementService
        self.workoutSessionController = workoutSessionController
        self.notificationScheduler = notificationScheduler
        self.extendedRuntimeController = extendedRuntimeController
        self.audioCuePlayer = audioCuePlayer

        let hold = UserDefaults.standard.object(forKey: Key.holdSeconds) as? Int ?? 30
        let shift = UserDefaults.standard.object(forKey: Key.shiftSeconds) as? Int ?? 10
        let announcements = UserDefaults.standard.object(forKey: Key.announcementsEnabled) as? Bool ?? true
        let total = UserDefaults.standard.object(forKey: Key.totalDurationSeconds) as? Int ?? Self.defaultTotalSeconds
        let storedVolume = UserDefaults.standard.object(forKey: Key.sessionVolume) as? Float ?? Self.defaultSessionVolume
        if let rawMode = UserDefaults.standard.string(forKey: Key.backgroundModeChoice) {
            backgroundModeChoice = BackgroundModeChoice(rawValue: rawMode)
        } else {
            backgroundModeChoice = nil
        }

        let initial = TimerSettings(holdSeconds: hold, shiftSeconds: shift, announcementsEnabled: announcements).clamped()
        let clampedTotal = min(max(total, Self.minTotalSeconds), Self.maxTotalSeconds)
        holdSeconds = initial.holdSeconds
        shiftSeconds = initial.shiftSeconds
        announcementsEnabled = initial.announcementsEnabled
        totalDurationSeconds = clampedTotal
        sessionVolume = min(max(storedVolume, 0.1), 1.0)
        remainingSeconds = initial.holdSeconds
        totalRemainingSeconds = clampedTotal
    }

    convenience init() {
        self.init(
            announcementService: AnnouncementService(),
            workoutSessionController: WorkoutSessionController(),
            notificationScheduler: NotificationScheduler(),
            extendedRuntimeController: ExtendedRuntimeSessionController(),
            audioCuePlayer: AudioCuePlayer()
        )
    }

    var needsOnboarding: Bool {
        backgroundModeChoice == nil
    }

    var showsHealthKitInDevelopmentNotice: Bool {
        backgroundModeChoice == .healthKit && !workoutSessionController.isAvailable
    }

    var isAnnouncementsAllowed: Bool {
        true
    }

    var phaseTitle: String {
        isRunning ? currentPhase.title : "Ready"
    }

    var totalDisplaySeconds: Int {
        isRunning ? totalRemainingSeconds : totalDurationSeconds
    }

    func selectBackgroundMode(_ mode: BackgroundModeChoice) {
        backgroundModeChoice = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Key.backgroundModeChoice)
        if mode == .alertsOnly {
            notificationScheduler.requestAuthorizationIfNeeded()
        }
    }

    func updateHoldSeconds(_ value: Int) {
        guard !isRunning else { return }
        let clamped = min(max(value, TimerSettings.minSeconds), TimerSettings.maxSeconds)
        holdSeconds = clamped
        remainingSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: Key.holdSeconds)
    }

    func updateShiftSeconds(_ value: Int) {
        guard !isRunning else { return }
        let clamped = min(max(value, TimerSettings.minSeconds), TimerSettings.maxSeconds)
        shiftSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: Key.shiftSeconds)
    }

    func updateAnnouncementsEnabled(_ value: Bool) {
        announcementsEnabled = value
        UserDefaults.standard.set(value, forKey: Key.announcementsEnabled)
    }

    func updateTotalDurationSeconds(_ value: Int) {
        guard !isRunning else { return }
        let clamped = min(max(value, Self.minTotalSeconds), Self.maxTotalSeconds)
        totalDurationSeconds = clamped
        totalRemainingSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: Key.totalDurationSeconds)
    }

    func updateSessionVolume(_ value: Float) {
        let clamped = min(max(value, 0.1), 1.0)
        sessionVolume = clamped
        UserDefaults.standard.set(clamped, forKey: Key.sessionVolume)
    }

    func incrementHold() {
        updateHoldSeconds(holdSeconds + TimerSettings.stepSeconds)
    }

    func decrementHold() {
        updateHoldSeconds(holdSeconds - TimerSettings.stepSeconds)
    }

    func incrementShift() {
        updateShiftSeconds(shiftSeconds + TimerSettings.stepSeconds)
    }

    func decrementShift() {
        updateShiftSeconds(shiftSeconds - TimerSettings.stepSeconds)
    }

    func start() {
        guard !isRunning else { return }

        sanitizeAndPersistSettings()
        isRunning = true
        currentPhase = .hold
        totalRemainingSeconds = totalDurationSeconds
        totalEndDate = Date().addingTimeInterval(TimeInterval(totalDurationSeconds))
        lastCountdownSecond = nil
        lastCuePhase = currentPhase

        startTickerIfNeeded()
        beginPhase(.hold)

        switch effectiveBackgroundMode {
        case .alertsOnly:
            notificationScheduler.requestAuthorizationIfNeeded()
        case .healthKit:
            workoutSessionController.startIfAvailable()
        }
    }

    func stop() {
        isRunning = false
        currentPhase = .hold
        phaseEndDate = nil
        totalEndDate = nil
        lastCountdownSecond = nil
        lastCuePhase = nil

        ticker?.cancel()
        ticker = nil

        extendedRuntimeController.stop()
        workoutSessionController.stop()
        notificationScheduler.clearAll()
        announcementService.stop()
        remainingSeconds = holdSeconds
        totalRemainingSeconds = totalDurationSeconds
    }

    private var effectiveBackgroundMode: BackgroundModeChoice {
        guard backgroundModeChoice == .healthKit else { return .alertsOnly }
        return workoutSessionController.isAvailable ? .healthKit : .alertsOnly
    }

    private func sanitizeAndPersistSettings() {
        let clean = TimerSettings(
            holdSeconds: holdSeconds,
            shiftSeconds: shiftSeconds,
            announcementsEnabled: announcementsEnabled
        ).clamped()

        holdSeconds = clean.holdSeconds
        shiftSeconds = clean.shiftSeconds
        announcementsEnabled = clean.announcementsEnabled

        UserDefaults.standard.set(clean.holdSeconds, forKey: Key.holdSeconds)
        UserDefaults.standard.set(clean.shiftSeconds, forKey: Key.shiftSeconds)
        UserDefaults.standard.set(clean.announcementsEnabled, forKey: Key.announcementsEnabled)
    }

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }

        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isRunning else { return }

        if let totalEndDate {
            let totalSeconds = max(0, Int(totalEndDate.timeIntervalSinceNow.rounded(.down)))
            totalRemainingSeconds = totalSeconds
            if totalSeconds == 0 {
                if WKExtension.shared().applicationState == .active {
                    announcementService.playSessionCompleteHaptic()
                }
                stop()
                return
            }
        }

        guard let endDate = phaseEndDate else { return }
        let seconds = max(0, Int(endDate.timeIntervalSinceNow.rounded(.down)))
        remainingSeconds = seconds

        if lastCuePhase != currentPhase {
            lastCountdownSecond = nil
            lastCuePhase = currentPhase
        }

        if seconds >= 1 && seconds <= 3 && lastCountdownSecond != seconds {
            lastCountdownSecond = seconds
            if shouldPlayForegroundAudio {
                playCountdownCue(for: currentPhase, second: seconds)
            }
        }

        if seconds == 0 {
            transitionToNextPhase()
        }
    }

    private func beginPhase(_ phase: TimerPhase) {
        currentPhase = phase
        let duration = duration(for: phase)
        remainingSeconds = duration
        phaseEndDate = Date().addingTimeInterval(TimeInterval(duration))

        if announcementsEnabled && !isDisplayDimmed {
            announcementService.announce(phase.startAnnouncement, volume: sessionVolume)
        }

        if effectiveBackgroundMode == .alertsOnly && !isDisplayDimmed {
            let totalRemaining = totalEndDate.map { max(0, Int($0.timeIntervalSinceNow.rounded(.down))) } ?? totalDurationSeconds
            let isFinalPhase = totalRemaining <= duration
            notificationScheduler.scheduleIntervalNotifications(phase: phase, duration: duration, isFinalPhase: isFinalPhase)
        }
    }

    private func transitionToNextPhase() {
        guard isRunning else { return }

        let completed = currentPhase
        if shouldPlayForegroundAudio {
            playEndCue(for: completed)
        }
        announcementService.playPhaseTransitionHaptic(for: completed)

        let next: TimerPhase = (completed == .hold) ? .shift : .hold
        beginPhase(next)
    }

    private func playCountdownCue(for phase: TimerPhase, second: Int) {
        let name: String
        switch (phase, second) {
        case (.hold, 3): name = "Audio/hold_3.aiff"
        case (.hold, 2): name = "Audio/hold_2.aiff"
        case (.hold, 1): name = "Audio/hold_1.aiff"
        case (.shift, 3): name = "Audio/shift_3.aiff"
        case (.shift, 2): name = "Audio/shift_2.aiff"
        case (.shift, 1): name = "Audio/shift_1.aiff"
        default: return
        }
        let multiplier: Float
        switch second {
        case 3: multiplier = 0.25
        case 2: multiplier = 0.5
        case 1: multiplier = 0.75
        default: multiplier = 1.0
        }
        audioCuePlayer.play(named: name, volume: sessionVolume * multiplier)
    }

    private func playEndCue(for phase: TimerPhase) {
        let name = (phase == .hold) ? "Audio/hold_end.aiff" : "Audio/shift_end.aiff"
        audioCuePlayer.play(named: name, volume: sessionVolume)
    }

    private func duration(for phase: TimerPhase) -> Int {
        switch phase {
        case .hold: return holdSeconds
        case .shift: return shiftSeconds
        }
    }

    var shouldPlayForegroundAudio: Bool {
        WKExtension.shared().applicationState == .active || isDisplayDimmed
    }

    func updateDisplayDimmed(_ dimmed: Bool) {
        isDisplayDimmed = dimmed
        if dimmed {
            announcementService.stop()
            notificationScheduler.clearPending()
        }
    }
}
