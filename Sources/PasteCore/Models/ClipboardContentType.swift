import Foundation

public enum ClipboardContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case url
    case image
    case file
    case richText
    case html
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: "Text"
        case .url: "URL"
        case .image: "Image"
        case .file: "File"
        case .richText: "Rich Text"
        case .html: "HTML"
        case .unknown: "Unknown"
        }
    }

    public var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        case .richText: "textformat"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .unknown: "questionmark.square"
        }
    }

    public var payloadFileExtension: String {
        switch self {
        case .text, .url: "txt"
        case .image: "img"
        case .file: "urls"
        case .richText: "rtf"
        case .html: "html"
        case .unknown: "bin"
        }
    }
}
