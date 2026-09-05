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
            Divider()
            playlistSection
        }
        .padding()
        .frame(width: 300)
        .background(isDropTargeted ? Color.accentColor.opacity(0.1) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .alert(
            "Error",
            isPresented: Binding(
                get: { audioManager.errorMessage != nil },
                set: { if !$0 { audioManager.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(audioManager.errorMessage ?? "")
        }
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

    @ViewBuilder
    private var playlistSection: some View {
        if audioManager.playlist.tracks.isEmpty {
            Text("Drop MP3, M4A or WAV files here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(audioManager.playlist.tracks) { track in
                        trackRow(track)
                    }
                }
            }
            .frame(maxHeight: 140)
        }
    }

    private func trackRow(_ track: Track) -> some View {
        let isCurrent = track.id == audioManager.currentTrack?.id

        return Text(track.title)
            .font(.subheadline)
            .lineLimit(1)
            .foregroundStyle(isCurrent ? Color.accentColor : .primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color.accentColor.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture {
                audioManager.play(trackWithId: track.id)
            }
    }

    private func formatted(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openFilePicker() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.level = .modalPanel

        panel.begin { response in
            guard response == .OK else { return }
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
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
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
