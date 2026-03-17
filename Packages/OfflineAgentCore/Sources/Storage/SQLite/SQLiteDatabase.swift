import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg),
             .execFailed(let msg),
             .prepareFailed(let msg),
             .bindFailed(let msg),
             .stepFailed(let msg):
            return msg
        }
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private let url: URL
    private var db: OpaquePointer?

    public init(url: URL) {
        self.url = url
    }

    deinit {
        close()
    }

    public func open() throws {
        if db != nil { return }

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        if sqlite3_open(url.path, &handle) != SQLITE_OK {
            throw SQLiteError.openFailed(lastError(handle))
        }
        db = handle

        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA foreign_keys=ON;")
    }

    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    public func exec(_ sql: String) throws {
        guard let db else { throw SQLiteError.openFailed("DB未打开") }
        var errMsg: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? lastError(db)
            sqlite3_free(errMsg)
            throw SQLiteError.execFailed(msg)
        }
    }

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let db else { throw SQLiteError.openFailed("DB未打开") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastError(db))
        }
        return SQLiteStatement(stmt: stmt)
    }

    private func lastError(_ db: OpaquePointer?) -> String {
        guard let db else { return "sqlite unknown error" }
        return String(cString: sqlite3_errmsg(db))
    }
}

public struct SQLiteStatement: @unchecked Sendable {
    fileprivate let stmt: OpaquePointer?

    fileprivate init(stmt: OpaquePointer?) {
        self.stmt = stmt
    }

    public func finalize() {
        sqlite3_finalize(stmt)
    }

    public func bindText(_ value: String, index: Int32) throws {
        let rc = sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        if rc != SQLITE_OK { throw SQLiteError.bindFailed("bindText失败") }
    }

    public func bindInt64(_ value: Int64, index: Int32) throws {
        let rc = sqlite3_bind_int64(stmt, index, value)
        if rc != SQLITE_OK { throw SQLiteError.bindFailed("bindInt64失败") }
    }

    public func bindBlob(_ value: Data, index: Int32) throws {
        let rc = value.withUnsafeBytes { rawBuf in
            sqlite3_bind_blob(stmt, index, rawBuf.baseAddress, Int32(rawBuf.count), SQLITE_TRANSIENT)
        }
        if rc != SQLITE_OK { throw SQLiteError.bindFailed("bindBlob失败") }
    }

    public func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SQLiteError.stepFailed("step失败 rc=\(rc)")
    }

    public func columnText(_ index: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cstr)
    }

    public func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    public func columnBlob(_ index: Int32) -> Data {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return Data() }
        let size = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: ptr, count: size)
    }
}

