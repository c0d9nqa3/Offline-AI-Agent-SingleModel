import Foundation

public enum StorageError: Error, LocalizedError {
    case keyUnavailable
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .keyUnavailable:
            return "存储密钥不可用"
        case .migrationFailed(let msg):
            return "迁移失败：\(msg)"
        }
    }
}

public final class EncryptedSQLiteStore: @unchecked Sendable {
    private let dbURL: URL
    private let db: SQLiteDatabase
    private let keychain: KeychainStore
    private let keyAccount: String

    public init(dbURL: URL, keychainService: String = "OfflineAgentCore.Store") {
        self.dbURL = dbURL
        self.db = SQLiteDatabase(url: dbURL)
        self.keychain = KeychainStore(service: keychainService)
        self.keyAccount = "db_dek_v1"
    }

    public func openAndMigrate() throws {
        try db.open()

        // SQLCipher support can be enabled later. We keep the call-site stable by
        // applying a "PRAGMA key" when available (SQLCipher interprets it).
        let key = try loadOrCreateDEK()
        let keyHex = key.map { String(format: "%02x", $0) }.joined()
        try? db.exec("PRAGMA key = \"x'\(keyHex)'\";")

        try migrate()
    }

    public func insertChatMessage(_ message: ChatMessage) throws {
        let stmt = try db.prepare("""
        INSERT INTO chat_messages(id, role, text, created_at)
        VALUES(?, ?, ?, ?);
        """)
        defer { stmt.finalize() }
        try stmt.bindText(message.id.uuidString, index: 1)
        try stmt.bindText(message.role.rawValue, index: 2)
        try stmt.bindText(message.text, index: 3)
        try stmt.bindInt64(Int64(message.createdAt.timeIntervalSince1970), index: 4)
        _ = try stmt.step()
    }

    public func loadRecentMessages(limit: Int = 50) throws -> [ChatMessage] {
        let stmt = try db.prepare("""
        SELECT id, role, text, created_at
        FROM chat_messages
        ORDER BY created_at DESC
        LIMIT ?;
        """)
        defer { stmt.finalize() }
        try stmt.bindInt64(Int64(limit), index: 1)

        var out: [ChatMessage] = []
        while try stmt.step() {
            let id = UUID(uuidString: stmt.columnText(0)) ?? UUID()
            let role = ChatRole(rawValue: stmt.columnText(1)) ?? .assistant
            let text = stmt.columnText(2)
            let createdAt = Date(timeIntervalSince1970: TimeInterval(stmt.columnInt64(3)))
            out.append(ChatMessage(id: id, role: role, text: text, createdAt: createdAt))
        }
        return out.reversed()
    }

    public func setSetting(key: String, value: String) throws {
        let stmt = try db.prepare("""
        INSERT INTO settings(key, value)
        VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value;
        """)
        defer { stmt.finalize() }
        try stmt.bindText(key, index: 1)
        try stmt.bindText(value, index: 2)
        _ = try stmt.step()
    }

    public func insertMemory(id: String, text: String, createdAt: Date = Date()) throws {
        let stmt = try db.prepare("""
        INSERT INTO memories(id, text, created_at)
        VALUES(?, ?, ?);
        """)
        defer { stmt.finalize() }
        try stmt.bindText(id, index: 1)
        try stmt.bindText(text, index: 2)
        try stmt.bindInt64(Int64(createdAt.timeIntervalSince1970), index: 3)
        _ = try stmt.step()
    }

    public func loadMemory(id: String) throws -> String? {
        let stmt = try db.prepare("""
        SELECT text FROM memories WHERE id=? LIMIT 1;
        """)
        defer { stmt.finalize() }
        try stmt.bindText(id, index: 1)
        if try stmt.step() {
            return stmt.columnText(0)
        }
        return nil
    }

    public func getSetting(key: String) throws -> String? {
        let stmt = try db.prepare("""
        SELECT value FROM settings WHERE key=? LIMIT 1;
        """)
        defer { stmt.finalize() }
        try stmt.bindText(key, index: 1)
        if try stmt.step() {
            return stmt.columnText(0)
        }
        return nil
    }

    public func wipeAll(deleteDBFile: Bool = true) throws {
        try? keychain.delete(account: keyAccount)
        db.close()
        if deleteDBFile {
            try? FileManager.default.removeItem(at: dbURL)
        }
    }

    private func migrate() throws {
        do {
            try db.exec("""
            CREATE TABLE IF NOT EXISTS schema_meta(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            """)
            try db.exec("""
            CREATE TABLE IF NOT EXISTS chat_messages(
              id TEXT PRIMARY KEY,
              role TEXT NOT NULL,
              text TEXT NOT NULL,
              created_at INTEGER NOT NULL
            );
            """)
            try db.exec("""
            CREATE TABLE IF NOT EXISTS settings(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            """)

            try db.exec("""
            CREATE TABLE IF NOT EXISTS memories(
              id TEXT PRIMARY KEY,
              text TEXT NOT NULL,
              created_at INTEGER NOT NULL
            );
            """)
        } catch {
            throw StorageError.migrationFailed(error.localizedDescription)
        }
    }

    private func loadOrCreateDEK() throws -> Data {
        if let existing = try keychain.getData(account: keyAccount) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw StorageError.keyUnavailable }
        let key = Data(bytes)
        try keychain.setData(key, account: keyAccount)
        return key
    }
}

