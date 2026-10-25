import Foundation
import SQLite3
import Testing
@testable import UsageBarCore

struct SQLiteReaderTests {
    /// Builds a throwaway database file with the given setup statements.
    private func makeDatabase(_ statements: [String]) throws -> String {
        let path = NSTemporaryDirectory() + "usagebar-test-\(UUID().uuidString).sqlite"
        var db: OpaquePointer?
        try #require(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for statement in statements {
            try #require(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
        }
        return path
    }

    @Test func boundParametersFilterRowsAndTypesComeBack() throws {
        let path = try makeDatabase([
            "create table message (provider text, created integer)",
            "insert into message values ('nvidia', 100), ('nvidia', 200), ('google', 300)",
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let rows = try #require(SQLiteReader(path: path).query(
            "select provider, count(*), max(created) from message where created >= ?1 and provider = ?2 group by 1",
            [.int(150), .text("nvidia")]
        ))
        #expect(rows.count == 1)
        #expect(rows[0][0].text == "nvidia")
        #expect(rows[0][1].int == 1)
        #expect(rows[0][2].int == 200)
    }

    @Test func nullColumnsAreReportedAsNull() throws {
        let path = try makeDatabase(["create table t (a text)", "insert into t values (NULL)"])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let rows = try #require(SQLiteReader(path: path).query("select a from t"))
        #expect(rows[0][0].text == nil)
        #expect(rows[0][0].int == nil)
    }

    @Test func aTextParameterIsNeverInterpretedAsSQL() throws {
        let path = try makeDatabase(["create table t (name text)", "insert into t values ('safe')"])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let rows = try #require(SQLiteReader(path: path).query(
            "select count(*) from t where name = ?1", [.text("x' OR '1'='1")]
        ))
        #expect(rows[0][0].int == 0)
    }

    @Test func writesAreRefused() throws {
        let path = try makeDatabase(["create table t (a integer)"])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(SQLiteReader(path: path).query("insert into t values (1)") == nil)
        let rows = try #require(SQLiteReader(path: path).query("select count(*) from t"))
        #expect(rows[0][0].int == 0)
    }

    @Test func aMissingFileReturnsNil() {
        #expect(SQLiteReader(path: "/nonexistent/db.sqlite").query("select 1") == nil)
    }
}
