import Foundation

enum PasteSettingsKeys {
    static let maxEntries = "ClipLAN.maxEntries"
    static let maxEntryMB = "ClipLAN.maxEntryMB"
    static let autoPaste = "ClipLAN.autoPaste"
    static let syncEnabled = "ClipLAN.syncEnabled"
    static let syncDiscoverable = "ClipLAN.syncDiscoverable"
    static let syncPairingCode = "ClipLAN.syncPairingCode"
    static let deviceName = "ClipLAN.deviceName"
    static let hotKeyPreset = "ClipLAN.hotKeyPreset"
    static let launchAtLogin = "ClipLAN.launchAtLogin"

    static let defaults: [String: Any] = [
        maxEntries: 10_000,
        maxEntryMB: 50,
        autoPaste: true,
        syncEnabled: true,
        syncDiscoverable: true,
        syncPairingCode: "",
        deviceName: Host.current().localizedName ?? "Mac",
        hotKeyPreset: HotKeyPreset.commandShiftV.rawValue,
        launchAtLogin: false
    ]
}

struct PasteRuntimeSettings {
    var maxEntries: Int
    var maxEntryBytes: Int
    var autoPaste: Bool
    var syncEnabled: Bool
    var syncDiscoverable: Bool
    var syncPairingCode: String
    var deviceName: String

    static func current(defaults: UserDefaults = .standard) -> PasteRuntimeSettings {
        PasteRuntimeSettings(
            maxEntries: max(100, defaults.integer(forKey: PasteSettingsKeys.maxEntries)),
            maxEntryBytes: max(1, defaults.integer(forKey: PasteSettingsKeys.maxEntryMB)) * 1024 * 1024,
            autoPaste: defaults.bool(forKey: PasteSettingsKeys.autoPaste),
            syncEnabled: defaults.bool(forKey: PasteSettingsKeys.syncEnabled),
            syncDiscoverable: defaults.bool(forKey: PasteSettingsKeys.syncDiscoverable),
            syncPairingCode: defaults.string(forKey: PasteSettingsKeys.syncPairingCode) ?? "",
            deviceName: defaults.string(forKey: PasteSettingsKeys.deviceName) ?? Host.current().localizedName ?? "Mac"
        )
    }
}
