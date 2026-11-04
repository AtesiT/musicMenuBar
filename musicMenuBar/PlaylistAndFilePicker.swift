import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import Observation

struct Playlist {

    private(set) var tracks: [Track] = []
    private(set) var currentIndex: Int?

    var currentTrack: Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    var isLastTrack: Bool {
        guard let currentIndex else { return true }
        return currentIndex >= tracks.count - 1
    }

    mutating func append(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
        if currentIndex == nil, !tracks.isEmpty {
            currentIndex = 0
        }
    }

    mutating func restore(tracks restoredTracks: [Track], currentIndex restoredIndex: Int?) {
        tracks = restoredTracks
        if let restoredIndex, restoredTracks.indices.contains(restoredIndex) {
            currentIndex = restoredIndex
        } else {
            currentIndex = restoredTracks.isEmpty ? nil : 0
        }
    }

    mutating func selectTrack(with id: Track.ID) {
        currentIndex = tracks.firstIndex { $0.id == id }
    }

    mutating func next() -> Track? {
        guard let currentIndex, !tracks.isEmpty else { return nil }
        let nextIndex = (currentIndex + 1) % tracks.count
        self.currentIndex = nextIndex
        return tracks[nextIndex]
    }

    mutating func previous() -> Track? {
        guard let currentIndex, !tracks.isEmpty else { return nil }
        let previousIndex = (currentIndex - 1 + tracks.count) % tracks.count
        self.currentIndex = previousIndex
        return tracks[previousIndex]
    }

    mutating func randomTrack() -> Track? {
        guard tracks.count > 1 else { return currentTrack }

        var candidates = Array(tracks.indices)
        if let currentIndex {
            candidates.removeAll { $0 == currentIndex }
        }

        guard let newIndex = candidates.randomElement() else { return currentTrack }
        currentIndex = newIndex
        return tracks[newIndex]
    }
}

struct Track: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
    let bookmark: Data?
}

private struct SavedPlaylist: Codable {
    var bookmarks: [Data]
    var currentIndex: Int?
}

enum FilePicker {
    static func presentForAudio(completion: @escaping ([URL]) -> Void) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.level = .modalPanel

        panel.begin { response in
            guard response == .OK else { return }
            completion(panel.urls)
        }
    }
}

@Observable
final class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {

    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isRepeatEnabled: Bool = false
    private(set) var playlist = Playlist()
    private(set) var isShuffleEnabled: Bool = false
    var errorMessage: String?

    var currentTrack: Track? { playlist.currentTrack }

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    private let savedPlaylistKey = "savedPlaylist"
    private let legacyLastTrackBookmarkKey = "lastTrackBookmark"

    override init() {
        super.init()
        restorePlaylist()
    }

    private static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav"]
    
    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }
    
    func toggleRepeat() {
        isRepeatEnabled.toggle()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }

        if isRepeatEnabled {
            seek(to: 0)
            play()
            return
        }

        let canAdvance = playlist.tracks.count > 1
            && (isShuffleEnabled || !playlist.isLastTrack)

        if canAdvance {
            next()
        } else {
            finishPlayback()
        }
    }
    
    func loadFiles(from urls: [URL]) {
        let validURLs = urls.filter {
            Self.supportedExtensions.contains($0.pathExtension.lowercased())
        }

        guard !validURLs.isEmpty else {
            errorMessage = "Supported formats: MP3, M4A, WAV"
            return
        }

        var seen = Set(playlist.tracks.map { $0.url.standardizedFileURL })
        let uniqueURLs = validURLs.filter { seen.insert($0.standardizedFileURL).inserted }

        guard !uniqueURLs.isEmpty else { return }

        let newTracks = uniqueURLs.map { makeTrack(url: $0) }
        let shouldAutoload = playlist.currentTrack == nil

        playlist.append(newTracks)
        persistPlaylist()

        if shouldAutoload, let first = playlist.currentTrack {
            load(track: first)
        }
    }
    
    func play(trackWithId id: Track.ID) {
        playlist.selectTrack(with: id)
        guard let track = playlist.currentTrack else { return }
        if load(track: track) {
            play()
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        if player == nil {
            guard let track = currentTrack, load(track: track) else { return }
        }

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
        advance { isShuffleEnabled ? playlist.randomTrack() : playlist.next() }
    }
    
    func previous() {
        advance { playlist.previous() }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    private func advance(using nextTrack: () -> Track?) {
        var failedTitles: [String] = []

        for _ in 0..<max(playlist.tracks.count, 1) {
            guard let track = nextTrack() else { break }

            if load(track: track, reportError: false) {
                play()
                break
            }
            failedTitles.append(track.title)
        }

        guard !failedTitles.isEmpty else { return }

        errorMessage = failedTitles.count == 1
            ? "Failed to load \"\(failedTitles[0])\""
            : "Failed to load \(failedTitles.count) tracks"
    }

    private func finishPlayback() {
        stopProgressTimer()
        isPlaying = false
        player?.currentTime = 0
        player?.prepareToPlay()
        currentTime = 0
    }

    @discardableResult
    private func load(track: Track, reportError: Bool = true) -> Bool {
        defer { persistPlaylist() }

        stopPlayback()

        guard let player = try? AVAudioPlayer(contentsOf: track.url) else {
            if reportError {
                errorMessage = "Failed to load \"\(track.title)\""
            }
            return false
        }

        player.delegate = self
        player.prepareToPlay()

        self.player = player
        duration = player.duration
        currentTime = 0

        return true
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
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func makeTrack(url: URL, bookmark: Data? = nil) -> Track {
        Track(
            title: url.deletingPathExtension().lastPathComponent,
            url: url,
            bookmark: bookmark ?? (try? url.bookmarkData(options: .withSecurityScope))
        )
    }

    private func persistPlaylist() {
        var bookmarks: [Data] = []
        var savedIndex: Int?

        for (index, track) in playlist.tracks.enumerated() {
            guard let bookmark = track.bookmark else { continue }
            if index == playlist.currentIndex {
                savedIndex = bookmarks.count
            }
            bookmarks.append(bookmark)
        }

        let saved = SavedPlaylist(bookmarks: bookmarks, currentIndex: savedIndex)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: savedPlaylistKey)
    }

    private func resolveBookmark(_ bookmark: Data) -> (url: URL, bookmark: Data)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }

        var actualBookmark = bookmark
        if isStale, let refreshed = try? url.bookmarkData(options: .withSecurityScope) {
            actualBookmark = refreshed
        }
        return (url, actualBookmark)
    }

    private func restorePlaylist() {
        let defaults = UserDefaults.standard
        var tracks: [Track] = []
        var restoredIndex: Int?

        if let data = defaults.data(forKey: savedPlaylistKey),
           let saved = try? JSONDecoder().decode(SavedPlaylist.self, from: data) {

            var seen = Set<URL>()

            for (index, bookmark) in saved.bookmarks.enumerated() {
                guard let resolved = resolveBookmark(bookmark),
                      seen.insert(resolved.url.standardizedFileURL).inserted else { continue }

                if index == saved.currentIndex {
                    restoredIndex = tracks.count
                }
                tracks.append(makeTrack(url: resolved.url, bookmark: resolved.bookmark))
            }
        } else if let legacy = defaults.data(forKey: legacyLastTrackBookmarkKey) {
            if let resolved = resolveBookmark(legacy) {
                tracks.append(makeTrack(url: resolved.url, bookmark: resolved.bookmark))
            }
            defaults.removeObject(forKey: legacyLastTrackBookmarkKey)
        }

        guard !tracks.isEmpty else { return }

        playlist.restore(tracks: tracks, currentIndex: restoredIndex)

        if let current = playlist.currentTrack {
            load(track: current, reportError: false)
        }
    }
}
