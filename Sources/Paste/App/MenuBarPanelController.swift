import AppKit
import SwiftUI

@MainActor
final class MenuBarPanelController: NSObject {
    static let shared = MenuBarPanelController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let windowSize = NSSize(width: 940, height: 620)
    private weak var model: ClipboardAppModel?
    private var panel: MenuBarPanel?
    private var hostingController: NSHostingController<AnyView>?

    func bind(model: ClipboardAppModel) {
        self.model = model
        configureStatusItemIfNeeded()
        model.start()
        FloatingPanelController.shared.bind(model: model)

        if let panel, panel.isVisible {
            hostingController?.rootView = makeRootView(model: model)
        }
    }

    func toggle() {
        guard let model else {
            return
        }

        if panel?.isVisible == true {
            hide()
        } else {
            show(model: model)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func show(model: ClipboardAppModel) {
        model.refresh()

        let panel = panel ?? makePanel(model: model)
        hostingController?.rootView = makeRootView(model: model)
        position(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func configureStatusItemIfNeeded() {
        guard let button = statusItem.button, statusItem.menu == nil else {
            return
        }

        statusItem.length = NSStatusItem.squareLength
        button.image = PasteLogoImageFactory.statusBarImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.toolTip = "ClipLAN"
        statusItem.menu = makeStatusMenu()
    }

    @objc private func openPasteFromMenu(_ sender: Any?) {
        guard let model else {
            return
        }
        show(model: model)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        guard let model else {
            return
        }
        SettingsWindowController.shared.show(model: model)
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "ClipLAN")
        menu.autoenablesItems = false

        let openItem = NSMenuItem(title: "Open ClipLAN", action: #selector(openPasteFromMenu(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ClipLAN", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makePanel(model: ClipboardAppModel) -> MenuBarPanel {
        let panel = MenuBarPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClipLAN"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .normal
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.minSize = NSSize(width: 862, height: 480)

        let hostingController = NSHostingController(rootView: makeRootView(model: model))
        panel.contentViewController = hostingController

        self.panel = panel
        self.hostingController = hostingController
        return panel
    }

    private func makeRootView(model: ClipboardAppModel) -> AnyView {
        AnyView(
            MenuBarWindowView(
                model: model,
                onOpenSettings: { [weak self, weak model] in
                    guard let model else {
                        return
                    }
                    self?.panel?.orderFrontRegardless()
                    SettingsWindowController.shared.show(model: model)
                }
            )
            .frame(minWidth: 862, minHeight: 480)
        )
    }

    private func position(_ panel: NSWindow) {
        let buttonFrame = statusButtonFrame()
        let screen = screenForFrame(buttonFrame) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - windowSize.width - 8
        let proposedX = buttonFrame.midX - windowSize.width / 2
        let x = min(max(proposedX, minX), maxX)
        let y = visibleFrame.maxY - windowSize.height - 8

        panel.setFrame(NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height), display: true)
    }

    private func statusButtonFrame() -> NSRect {
        guard let button = statusItem.button, let window = button.window else {
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            return NSRect(x: screenFrame.maxX - 80, y: screenFrame.maxY, width: 44, height: 24)
        }

        let windowRect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(windowRect)
    }

    private func screenForFrame(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.intersects(frame)
        }
    }
}

final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        orderOut(nil)
    }
}
