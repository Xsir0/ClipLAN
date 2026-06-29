import Foundation
import PasteCore

enum EntryFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case favorites
    case text
    case images
    case files
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .pinned: "Pinned"
        case .favorites: "Favorites"
        case .text: "Text"
        case .images: "Images"
        case .files: "Files"
        case .remote: "LAN"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case .favorites: "star"
        case .text: "text.alignleft"
        case .images: "photo"
        case .files: "doc"
        case .remote: "network"
        }
    }

    func includes(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .all:
            true
        case .pinned:
            entry.isPinned
        case .favorites:
            entry.isFavorite
        case .text:
            entry.type == .text || entry.type == .url || entry.type == .html || entry.type == .richText
        case .images:
            entry.type == .image
        case .files:
            entry.type == .file
        case .remote:
            entry.isRemote
        }
    }
}
