import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: ObservableObject {
    static let shared = FloatingPanelController()

    private var panel: FloatingClipboardPanel?
    private var hostingController: NSHostingController<FloatingPanelView>?
    private var model: ClipboardAppModel?
    private var hotKeyObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?

    func bind(model: ClipboardAppModel) {
        self.model = model
        guard hotKeyObserver == nil else {
            return
        }

        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: GlobalHotKeyNotification.pressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let model = self.model else {
                    return
                }
                self.toggle(model: model)
            }
        }
    }

    deinit {
        if let hotKeyObserver {
            NotificationCenter.default.removeObserver(hotKeyObserver)
        }
    }

    func toggle(model: ClipboardAppModel) {
        if panel?.isVisible == true {
            hide()
        } else {
            show(model: model)
        }
    }

    func show(model: ClipboardAppModel) {
        model.prepareForHotKeyActivation()
        model.refresh()

        let panel = panel ?? makePanel(model: model)
        configure(panel: panel, model: model)
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        installEventMonitors(for: panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        removeOutsideClickMonitors()

        guard let panel, panel.isVisible else {
            return
        }
        panel.orderOut(nil)
    }

    private func makePanel(model: ClipboardAppModel) -> FloatingClipboardPanel {
        let panel = FloatingClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 184),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.title = "ClipLAN Floating Panel"
        panel.onPrevious = { [weak model] in model?.selectPreviousFloatingEntry() }
        panel.onNext = { [weak model] in model?.selectNextFloatingEntry() }
        panel.onCommit = { [weak self, weak model] in
            guard let model else {
                return
            }
            self?.hide()
            model.paste(model.selectedEntry)
        }
        panel.onDismiss = { [weak self] in self?.hide() }
        panel.onLostKey = { [weak self] in self?.hide() }

        let view = FloatingPanelView(
            model: model,
            onPaste: { [weak self, weak model] entry in
                self?.hide()
                model?.paste(entry)
            }
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 14
        panel.contentViewController = hostingController

        self.panel = panel
        self.hostingController = hostingController
        return panel
    }

    private func configure(panel: FloatingClipboardPanel, model: ClipboardAppModel) {
        panel.onPrevious = { [weak model] in model?.selectPreviousFloatingEntry() }
        panel.onNext = { [weak model] in model?.selectNextFloatingEntry() }
        panel.onCommit = { [weak self, weak model] in
            guard let model else {
                return
            }
            self?.hide()
            model.paste(model.selectedEntry)
        }
        panel.onDismiss = { [weak self] in self?.hide() }
        panel.onLostKey = { [weak self] in self?.hide() }

        hostingController?.rootView = FloatingPanelView(
            model: model,
            onPaste: { [weak self, weak model] entry in
                self?.hide()
                model?.paste(entry)
            }
        )
    }

    private func position(_ panel: NSPanel) {
        let screen = screenForPanel() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(720, max(420, visibleFrame.width - 96))
        let height: CGFloat = 184
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.minY + 48
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func screenForPanel() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func installEventMonitors(for panel: FloatingClipboardPanel) {
        removeOutsideClickMonitors()

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let panel, panel.isVisible else {
                return event
            }

            if event.window !== panel {
                self?.hide()
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let panel, event.window === panel else {
                return event
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control])
            guard flags.isEmpty else {
                return event
            }

            switch event.keyCode {
            case 123:
                panel.onPrevious?()
                return nil
            case 124:
                panel.onNext?()
                return nil
            case 36, 76:
                panel.onCommit?()
                return nil
            case 53:
                self?.hide()
                return nil
            default:
                return event
            }
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}

final class FloatingClipboardPanel: NSPanel {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onCommit: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onLostKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        guard flags.isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123:
            onPrevious?()
        case 124:
            onNext?()
        case 36, 76:
            onCommit?()
        case 53:
            onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        onLostKey?()
    }
}
