import AppKit
import UniformTypeIdentifiers

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
