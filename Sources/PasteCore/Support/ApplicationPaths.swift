import Foundation

public enum ApplicationPaths {
    public static let supportFolderName = "ClipLAN"

    public static var appSupportURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportFolderName, isDirectory: true)
    }

    public static var blobsURL: URL {
        appSupportURL.appendingPathComponent("blobs", isDirectory: true)
    }

    public static var databaseURL: URL {
        appSupportURL.appendingPathComponent("clipboard.sqlite")
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: blobsURL,
            withIntermediateDirectories: true
        )
    }
}
