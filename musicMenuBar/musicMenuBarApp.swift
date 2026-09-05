import SwiftUI
import AppKit

@main
struct musicMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

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
        panel.styleMask = [.nonactivatingPanel, .titled, .fullSizeContentView]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.setContentSize(hosting.view.fittingSize)
        return panel
    }
}
