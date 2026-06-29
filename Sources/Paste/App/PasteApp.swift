import AppKit
import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: ClipboardAppModel

    @MainActor
    init() {
        UserDefaults.standard.register(defaults: PasteSettingsKeys.defaults)
        let appModel = ClipboardAppModel()
        _model = StateObject(wrappedValue: appModel)
        MenuBarPanelController.shared.bind(model: appModel)
    }

    var body: some Scene {
        Settings {
            SettingsView(model: model)
        }
    }
}
