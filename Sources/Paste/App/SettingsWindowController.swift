import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private let windowSize = NSSize(width: 740, height: 560)
    private let windowLevel = NSWindow.Level.normal

    func show(model: ClipboardAppModel) {
        if let window {
            hostingController?.rootView = SettingsView(model: model)
            window.setContentSize(windowSize)
            window.level = windowLevel
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipLAN Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.level = windowLevel
        window.minSize = windowSize
        window.center()

        self.window = window
        self.hostingController = hostingController

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
