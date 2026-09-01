import SwiftUI

@main
struct musicMenuBarApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var audioManager = AudioPlayerManager()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text(audioManager.currentTrack?.title ?? "No track loaded")
                    .font(.headline)
            }
            .padding()
            .frame(width: 240)
        } label: {
            Image(systemName: audioManager.isPlaying ? "waveform" : "music.note")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
