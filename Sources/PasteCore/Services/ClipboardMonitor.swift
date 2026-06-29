import AppKit
import Foundation

@MainActor
public final class ClipboardMonitor: NSObject {
    private let reader: ClipboardReader
    private let deviceID: String
    private var timer: Timer?
    private var lastChangeCount: Int
    private var maxBytes = 0

    public var onCapture: ((ClipboardEntry) -> Void)?
    public var onSkip: ((String) -> Void)?

    public init(reader: ClipboardReader, deviceID: String) {
        self.reader = reader
        self.deviceID = deviceID
        self.lastChangeCount = NSPasteboard.general.changeCount
        super.init()
    }

    public func start(pollInterval: TimeInterval = 0.6, maxBytes: Int) {
        stop()
        self.maxBytes = maxBytes
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(
            timeInterval: pollInterval,
            target: self,
            selector: #selector(handleTimer(_:)),
            userInfo: nil,
            repeats: true
        )
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

    @objc private func handleTimer(_ timer: Timer) {
        tick(maxBytes: maxBytes)
    }
}
