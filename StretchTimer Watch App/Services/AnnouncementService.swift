import AVFoundation
import WatchKit

@MainActor
final class AnnouncementService {
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        configureAudioSession()
    }

    func announce(_ text: String, volume: Float = 1.0) {
        #if targetEnvironment(simulator)
        return
        #endif
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = max(0.0, min(volume, 1.0))
        synthesizer.speak(utterance)
    }

    func playPhaseTransitionHaptic(for completedPhase: TimerPhase) {
        let haptic: WKHapticType = (completedPhase == .hold) ? .directionUp : .directionDown
        WKInterfaceDevice.current().play(haptic)
    }

    func playSessionCompleteHaptic() {
        WKInterfaceDevice.current().play(.success)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            // Keep running without voice if audio session setup fails.
        }
    }
}
