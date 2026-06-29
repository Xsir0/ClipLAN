import AppKit
import SwiftUI

struct KeyboardNavigationView: NSViewRepresentable {
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onCommit: () -> Void
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> KeyboardNavigationNSView {
        let view = KeyboardNavigationNSView()
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onCommit = onCommit
        view.onDismiss = onDismiss
        return view
    }

    func updateNSView(_ nsView: KeyboardNavigationNSView, context: Context) {
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onCommit = onCommit
        nsView.onDismiss = onDismiss
    }

    static func dismantleNSView(_ nsView: KeyboardNavigationNSView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

final class KeyboardNavigationNSView: NSView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onCommit: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else {
                return event
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control])
            guard flags.isEmpty else {
                return event
            }

            switch event.keyCode {
            case 123:
                self.onPrevious?()
                return nil
            case 124:
                self.onNext?()
                return nil
            case 36, 76:
                self.onCommit?()
                return nil
            case 53:
                self.onDismiss?()
                return nil
            default:
                return event
            }
        }
    }

    deinit {
        removeMonitor()
    }
}
