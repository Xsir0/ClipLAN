import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = GlobalHotKeyManager()
    private var hotKeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: PasteSettingsKeys.defaults)
        NSApp.setActivationPolicy(.accessory)
        hotKeyManager.register()
        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: HotKeySettingsNotification.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotKeyManager.register()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
        if let hotKeyObserver {
            NotificationCenter.default.removeObserver(hotKeyObserver)
        }
    }
}
