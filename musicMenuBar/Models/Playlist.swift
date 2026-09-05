import Foundation

struct Playlist {

    private(set) var tracks: [Track] = []
    private(set) var currentIndex: Int?

    var currentTrack: Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    mutating func append(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
        if currentIndex == nil, !tracks.isEmpty {
            currentIndex = 0
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
