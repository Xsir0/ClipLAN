import AppKit
import Foundation

public enum ClipboardReaderError: LocalizedError {
    case payloadTooLarge(Int)
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let bytes): "Clipboard payload is too large: \(bytes) bytes."
        case .unsupported: "Clipboard content type is not supported."
        }
    }
}

@MainActor
public final class ClipboardReader {
    private let payloadStore: PayloadStore

    public init(payloadStore: PayloadStore) {
        self.payloadStore = payloadStore
    }

    public func readCurrent(deviceID: String, maxBytes: Int) throws -> ClipboardEntry? {
        let pasteboard = NSPasteboard.general
        if pasteboard.types?.contains(PasteboardMarker.entryID) == true {
            return nil
        }

        if let fileEntry = try readFileURLs(from: pasteboard, deviceID: deviceID, maxBytes: maxBytes) {
            return fileEntry
        }

        if let imageEntry = try readImage(from: pasteboard, deviceID: deviceID, maxBytes: maxBytes) {
            return imageEntry
        }

        if let htmlEntry = try readDataType(.html, as: .html, from: pasteboard, deviceID: deviceID, maxBytes: maxBytes) {
            return htmlEntry
        }

        if let richTextEntry = try readDataType(.rtf, as: .richText, from: pasteboard, deviceID: deviceID, maxBytes: maxBytes) {
            return richTextEntry
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return try makeTextEntry(text, deviceID: deviceID, maxBytes: maxBytes)
        }

        return nil
    }

    private func readFileURLs(from pasteboard: NSPasteboard, deviceID: String, maxBytes: Int) throws -> ClipboardEntry? {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL]

        let urls = objects?.map { $0 as URL } ?? []
        guard !urls.isEmpty else {
            return nil
        }

        let payloadText = urls.map(\.absoluteString).joined(separator: "\n")
        let payload = Data(payloadText.utf8)
        try validateSize(payload.count, maxBytes: maxBytes)

        let hash = ContentHasher.sha256Hex(payload)
        let payloadPath = try payloadStore.savePayload(data: payload, hash: hash, type: .file)
        let preview = urls.map(\.lastPathComponent).joined(separator: ", ")

        return ClipboardEntry(
            deviceID: deviceID,
            contentHash: hash,
            type: .file,
            preview: Self.preview(preview.isEmpty ? payloadText : preview),
            sourceApp: sourceAppName(),
            payloadPath: payloadPath,
            byteSize: payload.count
        )
    }

    private func readImage(from pasteboard: NSPasteboard, deviceID: String, maxBytes: Int) throws -> ClipboardEntry? {
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let data, !data.isEmpty else {
            return nil
        }

        try validateSize(data.count, maxBytes: maxBytes)
        let hash = ContentHasher.sha256Hex(data)
        let payloadPath = try payloadStore.savePayload(data: data, hash: hash, type: .image)

        return ClipboardEntry(
            deviceID: deviceID,
            contentHash: hash,
            type: .image,
            preview: "Image • \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))",
            sourceApp: sourceAppName(),
            payloadPath: payloadPath,
            byteSize: data.count
        )
    }

    private func readDataType(
        _ pasteboardType: NSPasteboard.PasteboardType,
        as type: ClipboardContentType,
        from pasteboard: NSPasteboard,
        deviceID: String,
        maxBytes: Int
    ) throws -> ClipboardEntry? {
        guard let data = pasteboard.data(forType: pasteboardType), !data.isEmpty else {
            return nil
        }

        try validateSize(data.count, maxBytes: maxBytes)
        let hash = ContentHasher.sha256Hex(data)
        let payloadPath = try payloadStore.savePayload(data: data, hash: hash, type: type)
        let fallback = pasteboard.string(forType: .string) ?? type.displayName

        return ClipboardEntry(
            deviceID: deviceID,
            contentHash: hash,
            type: type,
            preview: Self.preview(fallback),
            sourceApp: sourceAppName(),
            payloadPath: payloadPath,
            byteSize: data.count
        )
    }

    private func makeTextEntry(_ text: String, deviceID: String, maxBytes: Int) throws -> ClipboardEntry {
        let payload = Data(text.utf8)
        try validateSize(payload.count, maxBytes: maxBytes)

        let type: ClipboardContentType = Self.isLikelyURL(text) ? .url : .text
        let hash = ContentHasher.sha256Hex(payload)
        let payloadPath = try payloadStore.savePayload(data: payload, hash: hash, type: type)

        return ClipboardEntry(
            deviceID: deviceID,
            contentHash: hash,
            type: type,
            preview: Self.preview(text),
            sourceApp: sourceAppName(),
            payloadPath: payloadPath,
            byteSize: payload.count
        )
    }

    private func validateSize(_ size: Int, maxBytes: Int) throws {
        if size > maxBytes {
            throw ClipboardReaderError.payloadTooLarge(size)
        }
    }

    private func sourceAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private static func preview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count <= 500 {
            return normalized
        }
        return String(normalized.prefix(497)) + "..."
    }

    private static func isLikelyURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        switch scheme {
        case "http", "https":
            return url.host?.isEmpty == false
        case "file", "mailto":
            return true
        default:
            return false
        }
    }
}
