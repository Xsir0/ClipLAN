import AppKit

enum PasteLogoImageFactory {
    static func statusBarImage(size: CGFloat = 18) -> NSImage {
        let symbolNames = ["doc.on.clipboard.fill", "doc.on.clipboard"]
        if let symbol = symbolNames
            .lazy
            .compactMap({ NSImage(systemSymbolName: $0, accessibilityDescription: "ClipLAN") })
            .first?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .bold)) {
            symbol.isTemplate = true
            return symbol
        }

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let scale = size / 18
        let lineWidth = max(1.2, 1.6 * scale)

        let back = NSBezierPath(
            roundedRect: NSRect(x: 4.2 * scale, y: 4.0 * scale, width: 8.8 * scale, height: 10.8 * scale),
            xRadius: 2.0 * scale,
            yRadius: 2.0 * scale
        )
        back.lineWidth = lineWidth
        back.stroke()

        let front = NSBezierPath(
            roundedRect: NSRect(x: 6.2 * scale, y: 2.8 * scale, width: 7.8 * scale, height: 10.6 * scale),
            xRadius: 2.0 * scale,
            yRadius: 2.0 * scale
        )
        front.lineWidth = lineWidth
        front.stroke()

        let clip = NSBezierPath(
            roundedRect: NSRect(x: 7.7 * scale, y: 13.2 * scale, width: 4.8 * scale, height: 2.0 * scale),
            xRadius: 0.9 * scale,
            yRadius: 0.9 * scale
        )
        clip.fill()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "ClipLAN"
        return image
    }
}
