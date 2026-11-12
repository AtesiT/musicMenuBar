import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import Observation

struct Track: Identifiable, Equatable {
    var id = UUID()
    let title: String
    let url: URL?
    let bookmark: Data?
}

struct Playlist {
    var tracks: [Track] = []
    var currentIndex: Int?

    var currentTrack: Track? {
        guard let index = currentIndex, tracks.indices.contains(index) else { return nil }
        return tracks[index]
    }

    var isLastTrack: Bool {
        guard let index = currentIndex else { return false }
        return index == tracks.count - 1
    }

    mutating func append(_ track: Track) {
        tracks.append(track)
    }

    mutating func restore(tracks: [Track], currentIndex: Int?) {
        self.tracks = tracks
        if let currentIndex, tracks.indices.contains(currentIndex) {
            self.currentIndex = currentIndex
        } else {
            self.currentIndex = tracks.isEmpty ? nil : 0
        }
    }

    mutating func replaceTrack(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[index] = track
    }

    @discardableResult
    mutating func selectTrack(with id: Track.ID) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        currentIndex = index
        return tracks[index]
    }

    mutating func next() -> Track? {
        guard let index = currentIndex, !tracks.isEmpty else { return nil }
        let nextIndex = (index + 1) % tracks.count
        currentIndex = nextIndex
        return tracks[nextIndex]
    }

    mutating func previous() -> Track? {
        guard let index = currentIndex, !tracks.isEmpty else { return nil }
        let previousIndex = (index - 1 + tracks.count) % tracks.count
        currentIndex = previousIndex
        return tracks[previousIndex]
    }

    mutating func randomTrack(excluding excluded: Set<Track.ID> = []) -> Track? {
        guard tracks.count > 1 else { return currentTrack }
        let candidates = tracks.indices.filter { index in
            index != currentIndex && !excluded.contains(tracks[index].id)
        }
        guard let index = candidates.randomElement() else { return nil }
        currentIndex = index
        return tracks[index]
    }
}

private struct SavedPlaylist: Codable {
    var bookmarks: [Data]
    var titles: [String]?
    var currentIndex: Int?
}

enum FilePicker {
    static func presentForAudio(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK {
                completion(panel.urls)
            }
        }
    }
}

@Observable
final class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isRepeatEnabled = false
    var playlist = Playlist()
    var isShuffleEnabled = false
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var accessedURLs: [URL: URL] = [:]

    @ObservationIgnored private let playlistKey = "savedPlaylist"
    @ObservationIgnored private let legacyBookmarkKey = "lastTrackBookmark"
    @ObservationIgnored private let unavailableTrackTitle = "Unavailable track"

    override init() {
        super.init()
        restorePlaylist()
    }

    deinit {
        for url in accessedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        guard flag else {
            handlePlaybackFailure()
            return
        }
        if isRepeatEnabled {
            seek(to: 0)
            play()
            return
        }
        let canAdvance = playlist.tracks.count > 1 && (isShuffleEnabled || !playlist.isLastTrack)
        if canAdvance {
            advanceToNext(stopsAtEnd: !isShuffleEnabled)
        } else {
            finishPlayback()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === self.player else { return }
        handlePlaybackFailure()
    }

    func loadFiles(_ urls: [URL]) {
        let supportedExtensions: Set<String> = ["mp3", "m4a", "wav"]
        let audioURLs = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard !audioURLs.isEmpty else {
            errorMessage = "Supported formats: MP3, M4A, WAV"
            return
        }

        revivePendingTracks()

        var seen = Set(playlist.tracks.compactMap { $0.url?.standardizedFileURL })
        let hadCurrentTrack = playlist.currentTrack != nil
        var added = false

        for url in audioURLs {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized).inserted else { continue }
            playlist.append(makeTrack(from: url))
            added = true
        }

        guard added else { return }

        if !hadCurrentTrack, let first = playlist.tracks.first {
            playlist.selectTrack(with: first.id)
            load(track: first, reportError: true)
        }
        persistPlaylist()
    }

    func play(trackWithId id: Track.ID) {
        let previousID = playlist.currentTrack?.id
        guard let track = playlist.selectTrack(with: id) else { return }
        if load(track: track, reportError: true) {
            play()
        } else if let previousID {
            playlist.selectTrack(with: previousID)
            persistPlaylist()
        }
    }

    func play() {
        if player == nil {
            guard let track = playlist.currentTrack,
                  load(track: track, reportError: true) else { return }
        }
        guard let player else { return }
        if player.play() {
            isPlaying = true
            startProgressTimer()
        } else {
            handlePlaybackFailure()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func next() {
        advanceToNext(stopsAtEnd: false)
    }

    func previous() {
        advance { [self] _ in playlist.previous() }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    private func advanceToNext(stopsAtEnd: Bool) {
        advance(stopsAtEnd: stopsAtEnd) { [self] excluded in
            isShuffleEnabled ? playlist.randomTrack(excluding: excluded) : playlist.next()
        }
    }

    private func advance(stopsAtEnd: Bool = false, using pick: (Set<Track.ID>) -> Track?) {
        guard let originalID = playlist.currentTrack?.id else { return }
        var excludedIDs: Set<Track.ID> = [originalID]
        var failedCount = 0
        var lastFailedTitle: String?
        var didLoad = false

        for _ in 0..<max(playlist.tracks.count - 1, 1) {
            if stopsAtEnd && playlist.isLastTrack { break }
            guard let track = pick(excludedIDs) else { break }
            excludedIDs.insert(track.id)
            if load(track: track, reportError: false) {
                didLoad = true
                play()
                break
            }
            failedCount += 1
            lastFailedTitle = track.title
        }

        guard !didLoad else { return }

        playlist.selectTrack(with: originalID)
        persistPlaylist()
        if isPlaying && player?.isPlaying != true {
            finishPlayback()
        }
        if failedCount == 1, let lastFailedTitle {
            errorMessage = "Failed to load \"\(lastFailedTitle)\""
        } else if failedCount > 1 {
            errorMessage = "Failed to load \(failedCount) tracks"
        }
    }

    private func finishPlayback() {
        stopProgressTimer()
        isPlaying = false
        player?.currentTime = 0
        player?.prepareToPlay()
        currentTime = 0
    }

    private func handlePlaybackFailure() {
        let title = playlist.currentTrack?.title
        stopProgressTimer()
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        if let title {
            errorMessage = "Playback failed for \"\(title)\""
        } else {
            errorMessage = "Playback failed"
        }
    }

    private func stopPlayback() {
        stopProgressTimer()
        player?.stop()
        isPlaying = false
    }

    private func revivePendingTracks() {
        for track in playlist.tracks where track.url == nil {
            _ = resolvedURL(for: track)
        }
    }

    private func resolvedURL(for track: Track) -> URL? {
        if let url = track.url { return url }
        guard let bookmark = track.bookmark,
              let resolved = resolveBookmark(bookmark) else { return nil }
        playlist.replaceTrack(Track(id: track.id, title: track.title, url: resolved.url, bookmark: resolved.bookmark))
        return resolved.url
    }

    private func relocatedURL(for track: Track, failedURL: URL) -> URL? {
        guard let bookmark = track.bookmark,
              let resolved = resolveBookmark(bookmark),
              resolved.url.standardizedFileURL != failedURL.standardizedFileURL else { return nil }
        playlist.replaceTrack(Track(id: track.id, title: track.title, url: resolved.url, bookmark: resolved.bookmark))
        return resolved.url
    }

    @discardableResult
    private func load(track: Track, reportError: Bool) -> Bool {
        defer { persistPlaylist() }

        guard let url = resolvedURL(for: track) else {
            if reportError {
                errorMessage = "Failed to load \"\(track.title)\""
            }
            return false
        }

        do {
            let newPlayer: AVAudioPlayer
            do {
                newPlayer = try AVAudioPlayer(contentsOf: url)
            } catch {
                guard let movedURL = relocatedURL(for: track, failedURL: url) else { throw error }
                newPlayer = try AVAudioPlayer(contentsOf: movedURL)
            }
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            stopPlayback()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
            return true
        } catch {
            if reportError {
                errorMessage = "Failed to load \"\(track.title)\""
            }
            return false
        }
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

    private func makeTrack(from url: URL) -> Track {
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return Track(
            title: url.deletingPathExtension().lastPathComponent,
            url: url,
            bookmark: bookmark
        )
    }

    private func persistPlaylist() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyBookmarkKey)

        var bookmarks: [Data] = []
        var titles: [String] = []
        var savedIndex: Int?

        for (index, track) in playlist.tracks.enumerated() {
            guard let bookmark = track.bookmark else { continue }
            if index == playlist.currentIndex {
                savedIndex = bookmarks.count
            }
            bookmarks.append(bookmark)
            titles.append(track.title)
        }

        guard !bookmarks.isEmpty else {
            defaults.removeObject(forKey: playlistKey)
            return
        }

        let saved = SavedPlaylist(bookmarks: bookmarks, titles: titles, currentIndex: savedIndex)
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: playlistKey)
        }
    }

    private func resolveBookmark(_ data: Data) -> (url: URL, bookmark: Data)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        let accessKey = url.standardizedFileURL
        if accessedURLs[accessKey] == nil, url.startAccessingSecurityScopedResource() {
            accessedURLs[accessKey] = url
        }

        var bookmark = data
        if isStale,
           let refreshed = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
           ) {
            bookmark = refreshed
        }
        return (url, bookmark)
    }

    private func restoreTrack(bookmark: Data, title: String?) -> Track {
        if let resolved = resolveBookmark(bookmark) {
            return Track(
                title: resolved.url.deletingPathExtension().lastPathComponent,
                url: resolved.url,
                bookmark: resolved.bookmark
            )
        }
        return Track(title: title ?? unavailableTrackTitle, url: nil, bookmark: bookmark)
    }

    private func restorePlaylist() {
        let defaults = UserDefaults.standard
        var saved: SavedPlaylist?

        if let data = defaults.data(forKey: playlistKey) {
            saved = try? JSONDecoder().decode(SavedPlaylist.self, from: data)
        } else if let legacy = defaults.data(forKey: legacyBookmarkKey) {
            saved = SavedPlaylist(bookmarks: [legacy], titles: nil, currentIndex: 0)
        }

        guard let saved else { return }

        var tracks: [Track] = []
        var indexByURL: [URL: Int] = [:]
        var currentIndex: Int?

        for (offset, bookmark) in saved.bookmarks.enumerated() {
            let savedTitle: String? = {
                guard let titles = saved.titles, titles.indices.contains(offset) else { return nil }
                return titles[offset]
            }()
            let track = restoreTrack(bookmark: bookmark, title: savedTitle)

            if let url = track.url?.standardizedFileURL {
                if let existing = indexByURL[url] {
                    if offset == saved.currentIndex {
                        currentIndex = existing
                    }
                    continue
                }
                indexByURL[url] = tracks.count
            }

            if offset == saved.currentIndex {
                currentIndex = tracks.count
            }
            tracks.append(track)
        }

        guard !tracks.isEmpty else { return }

        playlist.restore(tracks: tracks, currentIndex: currentIndex)
        if let track = playlist.currentTrack {
            load(track: track, reportError: false)
        }
    }
}
