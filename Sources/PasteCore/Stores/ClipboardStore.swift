import Foundation
import SQLite3

public enum ClipboardStoreError: LocalizedError {
    case openFailed(String)
    case sqlite(message: String)
    case missingDatabase

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): "Failed to open SQLite database: \(message)"
        case .sqlite(let message): "SQLite error: \(message)"
        case .missingDatabase: "SQLite database is not open."
        }
    }
}

public enum StoreMutation: Sendable {
    case inserted(ClipboardEntry)
    case updated(ClipboardEntry)

    public var entry: ClipboardEntry {
        switch self {
        case .inserted(let entry), .updated(let entry): entry
        }
    }

    public var inserted: Bool {
        if case .inserted = self {
            return true
        }
        return false
    }
}

public actor ClipboardStore {
    private let databaseURL: URL
    private var db: OpaquePointer?

    public init(databaseURL: URL = ApplicationPaths.databaseURL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
            throw ClipboardStoreError.openFailed(message)
        }

        do {
            try Self.configure(handle)
            try Self.migrate(handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
        self.db = handle
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func upsert(_ incoming: ClipboardEntry, maxEntries: Int) throws -> StoreMutation {
        if var existing = try fetchEntry(contentHash: incoming.contentHash) {
            existing.createdAt = max(existing.createdAt, incoming.createdAt)
            existing.updatedAt = Date()
            existing.sourceApp = incoming.sourceApp ?? existing.sourceApp
            existing.preview = incoming.preview.isEmpty ? existing.preview : incoming.preview
            existing.ocrText = incoming.ocrText ?? existing.ocrText
            existing.type = incoming.type == .unknown ? existing.type : incoming.type
            existing.remoteDeviceID = existing.remoteDeviceID ?? incoming.remoteDeviceID
            existing.isRemote = existing.isRemote || incoming.isRemote

            if existing.payloadPath == nil, let payloadPath = incoming.payloadPath {
                existing.payloadPath = payloadPath
                existing.byteSize = incoming.byteSize
            }

            try update(existing)
            _ = try prune(maxEntries: maxEntries)
            return .updated(existing)
        }

        try insert(incoming)
        _ = try prune(maxEntries: maxEntries)
        return .inserted(incoming)
    }

    public func fetchEntries(query: String = "", limit: Int = 200) throws -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try rows(
                sql: """
                SELECT id, device_id, content_hash, type, preview, ocr_text, source_app, payload_path, byte_size,
                       created_at, updated_at, is_favorite, is_pinned, is_remote, remote_device_id
                FROM entries
                ORDER BY is_pinned DESC, created_at DESC
                LIMIT ?;
                """,
                bindings: [.int(limit)]
            )
        }

        let ftsQuery = Self.ftsQuery(from: trimmed)
        guard !ftsQuery.isEmpty else {
            return try fetchEntries(limit: limit)
        }

        return try rows(
            sql: """
            SELECT e.id, e.device_id, e.content_hash, e.type, e.preview, e.ocr_text, e.source_app, e.payload_path, e.byte_size,
                   e.created_at, e.updated_at, e.is_favorite, e.is_pinned, e.is_remote, e.remote_device_id
            FROM entries e
            JOIN entries_fts f ON e.id = f.id
            WHERE entries_fts MATCH ?
            ORDER BY e.is_pinned DESC, e.created_at DESC
            LIMIT ?;
            """,
            bindings: [.text(ftsQuery), .int(limit)]
        )
    }

    public func fetchEntry(id: String) throws -> ClipboardEntry? {
        try rows(
            sql: """
            SELECT id, device_id, content_hash, type, preview, ocr_text, source_app, payload_path, byte_size,
                   created_at, updated_at, is_favorite, is_pinned, is_remote, remote_device_id
            FROM entries
            WHERE id = ?
            LIMIT 1;
            """,
            bindings: [.text(id)]
        ).first
    }

    public func fetchEntry(contentHash: String) throws -> ClipboardEntry? {
        try rows(
            sql: """
            SELECT id, device_id, content_hash, type, preview, ocr_text, source_app, payload_path, byte_size,
                   created_at, updated_at, is_favorite, is_pinned, is_remote, remote_device_id
            FROM entries
            WHERE content_hash = ?
            LIMIT 1;
            """,
            bindings: [.text(contentHash)]
        ).first
    }

    public func fetchRecentEntriesForSync(limit: Int = 100) throws -> [ClipboardEntry] {
        try rows(
            sql: """
            SELECT id, device_id, content_hash, type, preview, ocr_text, source_app, payload_path, byte_size,
                   created_at, updated_at, is_favorite, is_pinned, is_remote, remote_device_id
            FROM entries
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            bindings: [.int(limit)]
        )
    }

    public func updatePayloadPath(contentHash: String, payloadPath: String, byteSize: Int) throws {
        try execute(
            """
            UPDATE entries
            SET payload_path = ?, byte_size = ?, updated_at = ?
            WHERE content_hash = ?;
            """,
            bindings: [.text(payloadPath), .int(byteSize), .double(Date().timeIntervalSince1970), .text(contentHash)]
        )
    }

    public func updateOCRText(contentHash: String, ocrText: String?) throws -> ClipboardEntry? {
        let normalized = ocrText?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try execute(
            """
            UPDATE entries
            SET ocr_text = ?, updated_at = ?
            WHERE content_hash = ?;
            """,
            bindings: [.optionalText(normalized), .double(Date().timeIntervalSince1970), .text(contentHash)]
        )

        guard let entry = try fetchEntry(contentHash: contentHash) else {
            return nil
        }
        try refreshFTS(for: entry)
        return entry
    }

    public func setPinned(id: String, isPinned: Bool) throws {
        try execute(
            "UPDATE entries SET is_pinned = ?, updated_at = ? WHERE id = ?;",
            bindings: [.bool(isPinned), .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    public func setFavorite(id: String, isFavorite: Bool) throws {
        try execute(
            "UPDATE entries SET is_favorite = ?, updated_at = ? WHERE id = ?;",
            bindings: [.bool(isFavorite), .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    public func deleteEntry(id: String) throws -> String? {
        let payloadPath = try fetchEntry(id: id)?.payloadPath
        try execute("DELETE FROM entries_fts WHERE id = ?;", bindings: [.text(id)])
        try execute("DELETE FROM entries WHERE id = ?;", bindings: [.text(id)])
        return payloadPath
    }

    public func prune(maxEntries: Int) throws -> [String] {
        guard maxEntries > 0 else {
            return []
        }

        let candidates = try stringPairs(
            sql: """
            SELECT id, payload_path
            FROM entries
            WHERE id NOT IN (
                SELECT id FROM entries
                ORDER BY is_pinned DESC, created_at DESC
                LIMIT ?
            )
            AND is_pinned = 0
            AND is_favorite = 0;
            """,
            bindings: [.int(maxEntries)]
        )

        for candidate in candidates {
            try execute("DELETE FROM entries_fts WHERE id = ?;", bindings: [.text(candidate.0)])
            try execute("DELETE FROM entries WHERE id = ?;", bindings: [.text(candidate.0)])
        }

        return candidates.compactMap(\.1)
    }

    private static func configure(_ db: OpaquePointer?) throws {
        try exec(db, "PRAGMA journal_mode=WAL;")
        try exec(db, "PRAGMA synchronous=NORMAL;")
        try exec(db, "PRAGMA temp_store=MEMORY;")
        try exec(db, "PRAGMA mmap_size=268435456;")
        try exec(db, "PRAGMA foreign_keys=ON;")
    }

    private static func migrate(_ db: OpaquePointer?) throws {
        try exec(
            db,
            """
            CREATE TABLE IF NOT EXISTS entries (
                id TEXT PRIMARY KEY,
                device_id TEXT NOT NULL,
                content_hash TEXT NOT NULL UNIQUE,
                type TEXT NOT NULL,
                preview TEXT NOT NULL,
                ocr_text TEXT,
                source_app TEXT,
                payload_path TEXT,
                byte_size INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_remote INTEGER NOT NULL DEFAULT 0,
                remote_device_id TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_entries_created_at ON entries(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_entries_type ON entries(type);
            CREATE INDEX IF NOT EXISTS idx_entries_remote ON entries(is_remote);

            """
        )

        if try !tableHasColumn(db, table: "entries", column: "ocr_text") {
            try exec(db, "ALTER TABLE entries ADD COLUMN ocr_text TEXT;")
        }

        if try !tableHasColumn(db, table: "entries_fts", column: "ocr_text") {
            try exec(db, "DROP TABLE IF EXISTS entries_fts;")
            try exec(
                db,
                """
                CREATE VIRTUAL TABLE entries_fts
                USING fts5(id UNINDEXED, preview, source_app, ocr_text);
                INSERT INTO entries_fts (id, preview, source_app, ocr_text)
                SELECT id, preview, COALESCE(source_app, ''), COALESCE(ocr_text, '')
                FROM entries;
                """
            )
        }
    }

    private func insert(_ entry: ClipboardEntry) throws {
        try execute(
            """
            INSERT INTO entries (
                id, device_id, content_hash, type, preview, ocr_text, source_app, payload_path, byte_size,
                created_at, updated_at, is_favorite, is_pinned, is_remote, remote_device_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: bindings(for: entry)
        )
        try refreshFTS(for: entry)
    }

    private func update(_ entry: ClipboardEntry) throws {
        try execute(
            """
            UPDATE entries
            SET device_id = ?, content_hash = ?, type = ?, preview = ?, ocr_text = ?, source_app = ?, payload_path = ?,
                byte_size = ?, created_at = ?, updated_at = ?, is_favorite = ?, is_pinned = ?,
                is_remote = ?, remote_device_id = ?
            WHERE id = ?;
            """,
            bindings: [
                .text(entry.deviceID),
                .text(entry.contentHash),
                .text(entry.type.rawValue),
                .text(entry.preview),
                .optionalText(entry.ocrText),
                .optionalText(entry.sourceApp),
                .optionalText(entry.payloadPath),
                .int(entry.byteSize),
                .double(entry.createdAt.timeIntervalSince1970),
                .double(entry.updatedAt.timeIntervalSince1970),
                .bool(entry.isFavorite),
                .bool(entry.isPinned),
                .bool(entry.isRemote),
                .optionalText(entry.remoteDeviceID),
                .text(entry.id)
            ]
        )
        try refreshFTS(for: entry)
    }

    private func refreshFTS(for entry: ClipboardEntry) throws {
        try execute("DELETE FROM entries_fts WHERE id = ?;", bindings: [.text(entry.id)])
        try execute(
            "INSERT INTO entries_fts (id, preview, source_app, ocr_text) VALUES (?, ?, ?, ?);",
            bindings: [.text(entry.id), .text(entry.preview), .optionalText(entry.sourceApp), .optionalText(entry.ocrText)]
        )
    }

    private func bindings(for entry: ClipboardEntry) -> [SQLiteBinding] {
        [
            .text(entry.id),
            .text(entry.deviceID),
            .text(entry.contentHash),
            .text(entry.type.rawValue),
            .text(entry.preview),
            .optionalText(entry.ocrText),
            .optionalText(entry.sourceApp),
            .optionalText(entry.payloadPath),
            .int(entry.byteSize),
            .double(entry.createdAt.timeIntervalSince1970),
            .double(entry.updatedAt.timeIntervalSince1970),
            .bool(entry.isFavorite),
            .bool(entry.isPinned),
            .bool(entry.isRemote),
            .optionalText(entry.remoteDeviceID)
        ]
    }

    private func rows(sql: String, bindings: [SQLiteBinding] = []) throws -> [ClipboardEntry] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }

        var entries: [ClipboardEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(row(statement))
        }
        return entries
    }

    private func stringPairs(sql: String, bindings: [SQLiteBinding]) throws -> [(String, String?)] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }

        var pairs: [(String, String?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let payload = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            pairs.append((id, payload))
        }
        return pairs
    }

    private func row(_ statement: OpaquePointer?) -> ClipboardEntry {
        ClipboardEntry(
            id: text(statement, 0),
            deviceID: text(statement, 1),
            contentHash: text(statement, 2),
            type: ClipboardContentType(rawValue: text(statement, 3)) ?? .unknown,
            preview: text(statement, 4),
            ocrText: optionalText(statement, 5),
            sourceApp: optionalText(statement, 6),
            payloadPath: optionalText(statement, 7),
            byteSize: Int(sqlite3_column_int64(statement, 8)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            isFavorite: sqlite3_column_int(statement, 11) != 0,
            isPinned: sqlite3_column_int(statement, 12) != 0,
            isRemote: sqlite3_column_int(statement, 13) != 0,
            remoteDeviceID: optionalText(statement, 14)
        )
    }

    private func exec(_ sql: String) throws {
        guard let db else {
            throw ClipboardStoreError.missingDatabase
        }
        try Self.exec(db, sql)
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard let db else {
            throw ClipboardStoreError.missingDatabase
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw ClipboardStoreError.sqlite(message: message)
        }
    }

    private static func tableHasColumn(_ db: OpaquePointer?, table: String, column: String) throws -> Bool {
        guard let db else {
            throw ClipboardStoreError.missingDatabase
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) != SQLITE_OK {
            throw ClipboardStoreError.sqlite(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnName = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
               columnName == column {
                return true
            }
        }
        return false
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding]) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) != SQLITE_DONE {
            throw ClipboardStoreError.sqlite(message: lastErrorMessage)
        }
    }

    private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer? {
        guard let db else {
            throw ClipboardStoreError.missingDatabase
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw ClipboardStoreError.sqlite(message: lastErrorMessage)
        }

        for (index, binding) in bindings.enumerated() {
            try bind(binding, to: statement, at: Int32(index + 1))
        }

        return statement
    }

    private func bind(_ binding: SQLiteBinding, to statement: OpaquePointer?, at index: Int32) throws {
        let result: Int32
        switch binding {
        case .text(let value):
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        case .optionalText(let value):
            if let value {
                result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            } else {
                result = sqlite3_bind_null(statement, index)
            }
        case .int(let value):
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case .double(let value):
            result = sqlite3_bind_double(statement, index, value)
        case .bool(let value):
            result = sqlite3_bind_int(statement, index, value ? 1 : 0)
        }

        if result != SQLITE_OK {
            throw ClipboardStoreError.sqlite(message: lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        guard let db else {
            return "database is not open"
        }
        return String(cString: sqlite3_errmsg(db))
    }

    private static func ftsQuery(from query: String) -> String {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(8)
            .map { token in
                let trimmed = token.prefix(64)
                return "\(trimmed)*"
            }
            .joined(separator: " ")
    }
}

private enum SQLiteBinding {
    case text(String)
    case optionalText(String?)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
}
