import AppKit
import SwiftUI

struct MenuBarWindowView: View {
    @ObservedObject var model: ClipboardAppModel
    var onOpenSettings: () -> Void

    var body: some View {
        ContentView(model: model, onOpenSettings: onOpenSettings)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
