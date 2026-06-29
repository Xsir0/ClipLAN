import Foundation
import XCTest
@testable import PasteCore

final class ClipboardStoreTests: XCTestCase {
    func testUpsertDeduplicatesByContentHashAndSearches() async throws {
        let root = try temporaryDirectory()
        let store = try ClipboardStore(databaseURL: root.appendingPathComponent("clipboard.sqlite"))
        let hash = ContentHasher.sha256Hex("hello world")

        let first = ClipboardEntry(
            deviceID: "device-a",
            contentHash: hash,
            type: .text,
            preview: "hello world",
            sourceApp: "Tests",
            payloadPath: "blobs/he/hello.txt",
            byteSize: 11
        )

        let inserted = try await store.upsert(first, maxEntries: 100)
        XCTAssertTrue(inserted.inserted)

        var duplicate = first
        duplicate.id = UUID().uuidString
        duplicate.preview = "hello world again"

        let updated = try await store.upsert(duplicate, maxEntries: 100)
        XCTAssertFalse(updated.inserted)

        let all = try await store.fetchEntries(limit: 20)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.preview, "hello world again")

        let search = try await store.fetchEntries(query: "hello", limit: 20)
        XCTAssertEqual(search.count, 1)
        XCTAssertEqual(search.first?.contentHash, hash)

        let ocrUpdated = try await store.updateOCRText(contentHash: hash, ocrText: "invoice total 128")
        XCTAssertEqual(ocrUpdated?.ocrText, "invoice total 128")

        let ocrSearch = try await store.fetchEntries(query: "invoice", limit: 20)
        XCTAssertEqual(ocrSearch.count, 1)
        XCTAssertEqual(ocrSearch.first?.contentHash, hash)
    }

    func testPayloadStoreWritesByHashPath() throws {
        let root = try temporaryDirectory()
        let payloadStore = try PayloadStore(rootURL: root)
        let data = Data("payload".utf8)
        let hash = ContentHasher.sha256Hex(data)

        let relativePath = try payloadStore.savePayload(data: data, hash: hash, type: .text)
        let loaded = try payloadStore.loadPayload(relativePath: relativePath)

        XCTAssertEqual(loaded, data)
        XCTAssertTrue(relativePath.contains(String(hash.prefix(2))))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipLANTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
