import AppKit
import Foundation

@MainActor
public final class ClipboardMonitor {
    private let reader: ClipboardReader
    private let deviceID: String
    private var timer: Timer?
    private var lastChangeCount: Int

    public var onCapture: ((ClipboardEntry) -> Void)?
    public var onSkip: ((String) -> Void)?

    public init(reader: ClipboardReader, deviceID: String) {
        self.reader = reader
        self.deviceID = deviceID
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    public func start(pollInterval: TimeInterval = 0.6, maxBytes: Int) {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(maxBytes: maxBytes)
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(maxBytes: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        do {
            if let entry = try reader.readCurrent(deviceID: deviceID, maxBytes: maxBytes) {
                onCapture?(entry)
            }
        } catch {
            onSkip?(error.localizedDescription)
        }
    }
}
