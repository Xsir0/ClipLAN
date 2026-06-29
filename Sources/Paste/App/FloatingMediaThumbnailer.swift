import AppKit
import Foundation
import QuickLookThumbnailing

struct FloatingMediaPreview {
    var image: NSImage
    var kind: FloatingMediaKind
}

enum FloatingMediaKind {
    case clipboardImage
    case fileImage
    case fileVideo
}

final class FloatingMediaThumbnailer: @unchecked Sendable {
    static let shared = FloatingMediaThumbnailer()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 96
    }

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let key = "\(url.resolvingSymlinksInPath().path)|\(Int(size.width))x\(Int(size.height))@\(Int(scale))"
        if let cached = cachedThumbnail(forKey: key) {
            return cached
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self, key] representation, _ in
                let image = representation?.nsImage
                if let image {
                    self?.store(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func cachedThumbnail(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    private func store(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
