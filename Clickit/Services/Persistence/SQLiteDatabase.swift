import Foundation
import SQLite3

enum SQLiteError: LocalizedError {
    case openFailed(path: String, message: String)
    case statementFailed(sql: String, message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let message):
            "Could not open the Clickit database at \(path): \(message)"
        case .statementFailed(_, let message):
            "The Clickit database rejected a change: \(message)"
        }
    }
}

/// A value bound to a statement parameter.
enum SQLiteValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null

    static func text(_ value: String?) -> SQLiteValue {
        value.map { .text($0) } ?? .null
    }
}

/// Read accessors for the current result row. Indices are zero-based.
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    func int(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func bool(_ index: Int32) -> Bool {
        int(index) != 0
    }
}

/// A minimal wrapper over the system SQLite, which ships with macOS and is
/// therefore not a third-party dependency.
///
/// Deliberately small: Clickit needs parameter binding, row iteration and
/// transactions, and nothing else. A general-purpose query builder would be
/// more code to maintain than the handful of statements it would generate.
///
/// Not thread-safe by design. It is owned by a `@MainActor` store, so every
/// call already arrives on the main actor.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let path: String

    /// SQLite must copy bound strings, because Swift's buffers do not outlive
    /// the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        path = url.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(handle)
            throw SQLiteError.openFailed(path: path, message: message)
        }
        self.handle = handle

        // WAL survives an unclean shutdown far better than the rollback journal,
        // which matters because Clickit is usually killed rather than quit.
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no database handle"
    }

    // MARK: - Statements

    func execute(_ sql: String, _ parameters: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.statementFailed(sql: sql, message: lastErrorMessage)
        }
    }

    func query<T>(_ sql: String, _ parameters: [SQLiteValue] = [], row transform: (SQLiteRow) -> T) throws -> [T] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }

        var results: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                results.append(transform(SQLiteRow(statement: statement)))
            } else if result == SQLITE_DONE {
                return results
            } else {
                throw SQLiteError.statementFailed(sql: sql, message: lastErrorMessage)
            }
        }
    }

    private func prepare(_ sql: String, _ parameters: [SQLiteValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw SQLiteError.statementFailed(sql: sql, message: lastErrorMessage)
        }

        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch parameter {
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .int(let value): sqlite3_bind_int64(statement, index, Int64(value))
            case .double(let value): sqlite3_bind_double(statement, index, value)
            case .null: sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw SQLiteError.statementFailed(sql: sql, message: lastErrorMessage)
            }
        }
        return statement
    }

    /// Runs `work` in a transaction, rolling back if it throws. Used for
    /// multi-row writes so a partial delete cannot survive a failure.
    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Schema version

    var userVersion: Int32 {
        get throws {
            let versions = try query("PRAGMA user_version") { Int32($0.int(0)) }
            return versions.first ?? 0
        }
    }

    func setUserVersion(_ version: Int32) throws {
        // PRAGMA does not accept bound parameters, and this value is never
        // user-supplied.
        try execute("PRAGMA user_version = \(version)")
    }
}
