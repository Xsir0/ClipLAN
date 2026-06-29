import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyNotification {
    static let pressed = Notification.Name("ClipLAN.globalHotKeyPressed")
}

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case commandShiftV
    case commandOptionV
    case commandControlV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandShiftV: "Shift + Command + V"
        case .commandOptionV: "Option + Command + V"
        case .commandControlV: "Control + Command + V"
        }
    }

    var modifierFlags: UInt32 {
        switch self {
        case .commandShiftV:
            UInt32(cmdKey | shiftKey)
        case .commandOptionV:
            UInt32(cmdKey | optionKey)
        case .commandControlV:
            UInt32(cmdKey | controlKey)
        }
    }

    static func current(defaults: UserDefaults = .standard) -> HotKeyPreset {
        let rawValue = defaults.string(forKey: PasteSettingsKeys.hotKeyPreset) ?? Self.commandShiftV.rawValue
        return HotKeyPreset(rawValue: rawValue) ?? .commandShiftV
    }
}

enum HotKeySettingsNotification {
    static let changed = Notification.Name("ClipLAN.hotKeySettingsChanged")
}

final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register() {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(fourCharacterCode("PSTE")), id: 1)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKey()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            HotKeyPreset.current().modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func handleHotKey() {
        NotificationCenter.default.post(name: GlobalHotKeyNotification.pressed, object: nil)
    }

    private func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { result, character in
            (result << 8) + UInt32(character)
        }
    }
}
