import Foundation
import SQLite3

public final class LocalDatabase {
    public let url: URL
    private var db: OpaquePointer?
    private let encoder = JSONEncoder(), decoder = JSONDecoder()
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SentinelError.unavailable("Cannot open local SQLite database.") }
        sqlite3_busy_timeout(db, 3000)
        try execute("PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS snapshots (id INTEGER PRIMARY KEY, timestamp REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS snapshot_time ON snapshots(timestamp); CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, payload BLOB NOT NULL);")
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SentinelError.unavailable("Local database write failed.") }
    }
    public func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try encoder.encode(value)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO state(key,payload) VALUES(?,?)", -1, &stmt, nil) == SQLITE_OK else { throw SentinelError.unavailable("Local state preparation failed.") }
        defer { sqlite3_finalize(stmt) }
        _ = key.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SentinelError.unavailable("Local state write failed.") }
    }
    public func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM state WHERE key=?", -1, &stmt, nil) == SQLITE_OK else { throw SentinelError.unavailable("Local state read failed.") }
        defer { sqlite3_finalize(stmt) }
        _ = key.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
        return try decoder.decode(type, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    public func append(_ snapshot: UsageSnapshot, now: Date = Date()) throws {
        let data = try encoder.encode(snapshot)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO snapshots(timestamp,payload) VALUES(?,?)", -1, &stmt, nil) == SQLITE_OK else { throw SentinelError.unavailable("Snapshot preparation failed.") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, snapshot.timestamp.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SentinelError.unavailable("Snapshot write failed.") }
        try execute("DELETE FROM snapshots WHERE timestamp < \(now.addingTimeInterval(-35*86400).timeIntervalSince1970)")
    }
    public func snapshots() throws -> [UsageSnapshot] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM snapshots ORDER BY timestamp", -1, &stmt, nil) == SQLITE_OK else { throw SentinelError.unavailable("History read failed.") }
        defer { sqlite3_finalize(stmt) }
        var values: [UsageSnapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            values.append(try decoder.decode(UsageSnapshot.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))))
        }
        return values
    }
}
