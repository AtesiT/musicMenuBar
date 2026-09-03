import Foundation
import AVFoundation
import Observation

@Observable
final class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {

    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playlist = Playlist()

    var currentTrack: Track? { playlist.currentTrack }

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    private let lastTrackBookmarkKey = "lastTrackBookmark"

    override init() {
        super.init()
        restoreLastTrack()
    }

    func loadFiles(from urls: [URL]) {
        let newTracks = urls.map { Track(title: $0.deletingPathExtension().lastPathComponent, url: $0) }
        let shouldAutoload = playlist.currentTrack == nil

        playlist.append(newTracks)

        if shouldAutoload, let first = playlist.currentTrack {
            load(track: first)
        }
    }

    func play(trackWithId id: Track.ID) {
        playlist.selectTrack(with: id)
        guard let track = playlist.currentTrack else { return }
        load(track: track)
        play()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func next() {
        guard let track = playlist.next() else { return }
        load(track: track)
        play()
    }

    func previous() {
        guard let track = playlist.previous() else { return }
        load(track: track)
        play()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func load(track: Track) {
        stopPlayback()

        guard let player = try? AVAudioPlayer(contentsOf: track.url) else { return }
        player.delegate = self
        player.prepareToPlay()

        self.player = player
        duration = player.duration
        currentTime = 0

        saveLastTrackBookmark(for: track.url)
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        next()
    }

    private func saveLastTrackBookmark(for url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        UserDefaults.standard.set(bookmark, forKey: lastTrackBookmarkKey)
    }

    private func restoreLastTrack() {
        guard let bookmark = UserDefaults.standard.data(forKey: lastTrackBookmarkKey) else { return }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        loadFiles(from: [url])
    }
}
