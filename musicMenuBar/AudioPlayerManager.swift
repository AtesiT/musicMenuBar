import Foundation
import AVFoundation
import Observation

struct Track: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
}

@Observable
final class AudioPlayerManager {

    private(set) var isPlaying: Bool = false
    private(set) var currentTrack: Track?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?

    func loadTrack(from url: URL) {
        // TODO: инициализация AVAudioPlayer, обновление currentTrack и duration
    }

    func togglePlayback() {
        // TODO: play/pause логика
    }
}
