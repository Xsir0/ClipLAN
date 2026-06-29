import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: ClipboardAppModel

    var body: some View {
        Button("Open ClipLAN") {
            bringMainWindowForward()
        }

        Divider()

        ForEach(model.entries.prefix(6)) { entry in
            Button(shortTitle(entry.preview)) {
                model.paste(entry)
            }
        }

        Divider()

        Button("Restart LAN Sync") {
            model.restartServices()
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func bringMainWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "ClipLAN" }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func shortTitle(_ title: String) -> String {
        if title.count <= 30 {
            return title.isEmpty ? "Untitled" : title
        }
        return String(title.prefix(27)) + "..."
    }
}
