import Foundation

public struct DataWiper {
    private let paths: AppPaths
    private let store: EncryptedSQLiteStore
    private let encryptedFiles: EncryptedFileStore
    private let keychain: KeychainStore

    public init(paths: AppPaths, keychainService: String = "OfflineAgentCore.Store") {
        self.paths = paths
        self.store = EncryptedSQLiteStore(dbURL: paths.dbURL, keychainService: keychainService)
        self.encryptedFiles = EncryptedFileStore()
        self.keychain = KeychainStore(service: keychainService)
    }

    public func wipeAll() throws {
        try store.wipeAll(deleteDBFile: true)
        try? encryptedFiles.delete(at: paths.encryptedVectorIndexURL)

        // Best-effort: if we later add more DEKs, delete them here.
        try? keychain.delete(account: "faiss_dek_v1")
    }
}

