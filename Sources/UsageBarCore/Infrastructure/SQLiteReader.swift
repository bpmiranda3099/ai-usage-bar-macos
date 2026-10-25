import Foundation
import SQLite3

/// Read-only access to a SQLite file. Queries are always parameterized (values are
/// bound, never concatenated), and the connection refuses writes.
struct SQLiteReader {
    enum Param {
        case int(Int64)
        case text(String)
    }

    enum Cell {
        case int(Int64)
        case text(String)
        case null

        var int: Int64? {
            if case .int(let value) = self { return value }
            return nil
        }

        var text: String? {
            if case .text(let value) = self { return value }
            return nil
        }
    }

    let path: String

    /// Rows for `sql`, or nil if the file can't be opened or the statement fails.
    func query(_ sql: String, _ params: [Param] = []) -> [[Cell]]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        // SQLite copies the text during the bind call when given SQLITE_TRANSIENT.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            switch param {
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, transient)
            }
        }

        var rows: [[Cell]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: return .int(sqlite3_column_int64(statement, column))
                    case SQLITE_TEXT: return sqlite3_column_text(statement, column).map { .text(String(cString: $0)) } ?? .null
                    default: return .null
                    }
                })
            case SQLITE_DONE:
                return rows
            default:
                return nil
            }
        }
    }
}
