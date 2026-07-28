import Foundation
import SQLite3

enum SQLiteBind {
    case int(Int64)
    case text(String)
}

struct SQLiteRow {
    let stmt: OpaquePointer

    func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }

    func text(_ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    func blob(_ i: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, i) else { return nil }
        let n = sqlite3_column_bytes(stmt, i)
        guard n > 0 else { return nil }
        return Data(bytes: bytes, count: Int(n))
    }
}

enum SQLiteError: LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let m):    return "Could not open database: \(m)"
        case .prepare(let m): return "Query prepare failed: \(m)"
        case .step(let m):    return "Query step failed: \(m)"
        }
    }
}

/// chat.db is live WAL: open read-only without immutable, use fresh connections, and tolerate concurrent writers.
final class SQLiteReadOnly {
    private var db: OpaquePointer?

    // SQLITE_TRANSIENT makes SQLite copy bound text before Swift releases its bytes.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, db != nil else {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "unknown"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.open(msg)
        }
        sqlite3_busy_timeout(db, 3000)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    func query(_ sql: String, _ binds: [SQLiteBind] = [], each: (SQLiteRow) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        for (idx, bind) in binds.enumerated() {
            let i = Int32(idx + 1)
            switch bind {
            case .int(let v):  sqlite3_bind_int64(stmt, i, v)
            case .text(let v): sqlite3_bind_text(stmt, i, v, -1, Self.transient)
            }
        }

        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW:  each(SQLiteRow(stmt: stmt!))
            case SQLITE_DONE: return
            default:          throw SQLiteError.step(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}
