import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

struct PlayerView: View {

    @Environment(AudioPlayerManager.self) private var audioManager
    @State private var isSeeking = false
    @State private var seekValue: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            trackTitle
            progressSection
            controls
        }
        .padding()
        .frame(width: 260)
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
        HStack {
            Button(action: openFilePicker) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(action: audioManager.togglePlayback) {
                Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
            }
            .buttonStyle(.borderless)
            .disabled(audioManager.currentTrack == nil)

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
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            audioManager.loadTrack(from: url)
        }
    }
}
