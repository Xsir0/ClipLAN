import Foundation

public enum DeviceIdentity {
    private static let defaultsKey = "ClipLAN.deviceID"

    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }

        let id = UUID().uuidString
        defaults.set(id, forKey: defaultsKey)
        return id
    }
}
