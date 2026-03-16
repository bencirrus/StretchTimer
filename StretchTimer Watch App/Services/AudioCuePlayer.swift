import AVFoundation
import Foundation

@MainActor
final class AudioCuePlayer {
    private var players: [String: AVAudioPlayer] = [:]

    func play(named name: String, volume: Float) {
        #if targetEnvironment(simulator)
        return
        #endif
        if let player = players[name] {
            player.currentTime = 0
            player.volume = volume
            player.play()
            return
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            return
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue == 0 {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            players[name] = player
            player.play()
        } catch {
            // Ignore audio failures to avoid disrupting timer.
        }
    }
}
