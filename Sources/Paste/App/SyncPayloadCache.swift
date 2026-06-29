import Foundation
import PasteCore

final class SyncPayloadCache: @unchecked Sendable {
    private let payloadStore: PayloadStore
    private let lock = NSLock()
    private var entries: [String: ClipboardEntry] = [:]

    init(payloadStore: PayloadStore) {
        self.payloadStore = payloadStore
    }

    func update(_ entries: [ClipboardEntry]) {
        lock.lock()
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.contentHash, $0) })
        lock.unlock()
    }

    func providedPayload(for contentHash: String) -> ProvidedSyncPayload? {
        lock.lock()
        let entry = entries[contentHash]
        lock.unlock()

        guard let entry, let payloadPath = entry.payloadPath else {
            return nil
        }

        do {
            let data = try payloadStore.loadPayload(relativePath: payloadPath)
            return ProvidedSyncPayload(entry: entry, data: data)
        } catch {
            return nil
        }
    }
}
