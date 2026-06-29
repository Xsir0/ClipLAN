import Foundation

public final class PayloadStore: @unchecked Sendable {
    public let rootURL: URL
    public let blobsURL: URL

    public init(rootURL: URL = ApplicationPaths.appSupportURL) throws {
        self.rootURL = rootURL
        self.blobsURL = rootURL.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    }

    public func savePayload(data: Data, hash: String, type: ClipboardContentType) throws -> String {
        let prefix = String(hash.prefix(2))
        let folder = blobsURL.appendingPathComponent(prefix, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileName = "\(hash).\(type.payloadFileExtension)"
        let fileURL = folder.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: [.atomic])
        }
        return "blobs/\(prefix)/\(fileName)"
    }

    public func loadPayload(relativePath: String) throws -> Data {
        try Data(contentsOf: url(for: relativePath), options: [.mappedIfSafe])
    }

    public func deletePayload(relativePath: String) {
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }

    public func url(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }
}
