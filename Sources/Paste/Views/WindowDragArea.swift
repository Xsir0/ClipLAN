import AppKit
import SwiftUI

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggingView {
        DraggingView()
    }

    func updateNSView(_ nsView: DraggingView, context: Context) {}
}

final class DraggingView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
