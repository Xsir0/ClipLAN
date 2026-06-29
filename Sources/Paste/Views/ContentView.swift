import AppKit
import PasteCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ClipboardAppModel
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model, onOpenSettings: onOpenSettings)
                .frame(width: 220)

            Divider()

            EntryListView(model: model)
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)

            Divider()

            EntryDetailView(model: model, entry: model.selectedEntry)
                .frame(minWidth: 280, maxWidth: .infinity)
        }
        .frame(minWidth: 862, minHeight: 480)
        .background {
            KeyboardNavigationView(
                onPrevious: { model.selectPreviousEntry() },
                onNext: { model.selectNextEntry() },
                onCommit: { model.paste(model.selectedEntry) },
                onDismiss: { NSApp.keyWindow?.orderOut(nil) }
            )
            .frame(width: 0, height: 0)
        }
    }
}
