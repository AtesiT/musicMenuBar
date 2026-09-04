import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PlayerView: View {

    @Environment(AudioPlayerManager.self) private var audioManager
    @State private var isSeeking = false
    @State private var seekValue: TimeInterval = 0
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            trackTitle
            progressSection
            controls
        }
        .padding()
        .frame(width: 280)
        .background(isDropTargeted ? Color.accentColor.opacity(0.1) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var trackTitle: some View {
        Text(audioManager.currentTrack?.title ?? "No track loaded")
            .font(.headline)
            .lineLimit(1)
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekValue : audioManager.currentTime },
                    set: { seekValue = $0 }
                ),
                in: 0...max(audioManager.duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        audioManager.seek(to: seekValue)
                    }
                }
            )
            .disabled(audioManager.currentTrack == nil)

            HStack {
                Text(formatted(isSeeking ? seekValue : audioManager.currentTime))
                Spacer()
                Text(formatted(audioManager.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button(action: openFilePicker) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(action: audioManager.previous) {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(audioManager.playlist.tracks.count < 2)

            Button(action: audioManager.togglePlayback) {
                Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
            }
            .buttonStyle(.borderless)
            .disabled(audioManager.currentTrack == nil)

            Button(action: audioManager.next) {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(audioManager.playlist.tracks.count < 2)

            Spacer()
        }
    }

    private func formatted(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3]
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            audioManager.loadFiles(from: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "mp3" else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            audioManager.loadFiles(from: urls)
        }

        return true
    }
}
