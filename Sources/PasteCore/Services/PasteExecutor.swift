import AppKit
import ApplicationServices
import Foundation

public enum PasteExecutorError: LocalizedError {
    case missingPayload
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .missingPayload: "The clipboard entry does not have a local payload yet."
        case .invalidPayload: "The clipboard entry payload is invalid."
        }
    }
}

@MainActor
public final class PasteExecutor {
    private let payloadStore: PayloadStore

    public init(payloadStore: PayloadStore) {
        self.payloadStore = payloadStore
    }

    public func copyToPasteboard(_ entry: ClipboardEntry) throws {
        guard let payloadPath = entry.payloadPath else {
            throw PasteExecutorError.missingPayload
        }

        let data = try payloadStore.loadPayload(relativePath: payloadPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.type {
        case .text, .url:
            guard let text = String(data: data, encoding: .utf8) else {
                throw PasteExecutorError.invalidPayload
            }
            pasteboard.declareTypes([.string, PasteboardMarker.entryID], owner: nil)
            pasteboard.setString(text, forType: .string)
        case .html:
            pasteboard.declareTypes([.html, .string, PasteboardMarker.entryID], owner: nil)
            pasteboard.setData(data, forType: .html)
            pasteboard.setString(entry.preview, forType: .string)
        case .richText:
            pasteboard.declareTypes([.rtf, .string, PasteboardMarker.entryID], owner: nil)
            pasteboard.setData(data, forType: .rtf)
            pasteboard.setString(entry.preview, forType: .string)
        case .image:
            guard let image = NSImage(data: data) else {
                throw PasteExecutorError.invalidPayload
            }
            let tiffData = image.tiffRepresentation ?? data
            pasteboard.declareTypes([.tiff, PasteboardMarker.entryID], owner: nil)
            pasteboard.setData(tiffData, forType: .tiff)
        case .file:
            guard let text = String(data: data, encoding: .utf8) else {
                throw PasteExecutorError.invalidPayload
            }
            let urls = text
                .split(separator: "\n")
                .compactMap { URL(string: String($0)) }
                .map { $0 as NSURL }
            guard !urls.isEmpty else {
                throw PasteExecutorError.invalidPayload
            }
            pasteboard.writeObjects(urls)
            pasteboard.addTypes([PasteboardMarker.entryID], owner: nil)
        case .unknown:
            pasteboard.declareTypes([.string, PasteboardMarker.entryID], owner: nil)
            pasteboard.setString(entry.preview, forType: .string)
        }

        try writeMarker(entry.id, to: pasteboard)
    }

    private func writeMarker(_ entryID: String, to pasteboard: NSPasteboard) throws {
        _ = pasteboard.setString(entryID, forType: PasteboardMarker.entryID)
        guard pasteboard.types?.contains(PasteboardMarker.entryID) == true else {
            throw PasteExecutorError.invalidPayload
        }
    }

    public func paste(_ entry: ClipboardEntry, autoPaste: Bool, targetApplication: NSRunningApplication? = nil) throws {
        try copyToPasteboard(entry)
        guard autoPaste else {
            return
        }

        if let targetApplication {
            targetApplication.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                Self.sendCommandV()
            }
        } else {
            Self.sendCommandV()
        }
    }

    public static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeForV: CGKeyCode = 0x09
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
