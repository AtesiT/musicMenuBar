import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct musicMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private let audioManager = AudioPlayerManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: nil
        )
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }
    
    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            togglePanel()
            return
        }
        showContextMenu()
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        //menu.appearance = NSAppearance(named: .aqua)
        
        let addItem = NSMenuItem(title: "Add Music…", action: #selector(addMusic), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        guard let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
    
    @objc private func addMusic() {
        FilePicker.presentForAudio { [weak self] urls in
            self?.audioManager.loadFiles(from: urls)
        }
    }
    
    @objc private func quit() {
        NSApp.terminate(nil)
    }
    
    private func togglePanel() {
        guard let panel, panel.isVisible else {
            showPanel()
            return
        }
        panel.orderOut(nil)
    }
    
    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        
        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height - 4
        )
        
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(
            rootView: PlayerView().environment(audioManager)
        )
        
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        
        let fixedWidth: CGFloat = 300
        panel.minSize = NSSize(width: fixedWidth, height: 280)
        panel.maxSize = NSSize(width: fixedWidth, height: 600)
        panel.setContentSize(NSSize(width: fixedWidth, height: 320))
        
        return panel
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

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
        .frame(minHeight: 280, maxHeight: .infinity)
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
            Button(action: audioManager.toggleShuffle) {
                Image(systemName: "shuffle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(audioManager.isShuffleEnabled ? Color.accentColor : .secondary)

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

            Button(action: audioManager.toggleRepeat) {
                Image(systemName: "repeat")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(audioManager.isRepeatEnabled ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
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
            .frame(maxHeight: .infinity)
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

