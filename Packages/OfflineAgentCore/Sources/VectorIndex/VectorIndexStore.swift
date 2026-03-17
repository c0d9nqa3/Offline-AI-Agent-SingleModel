import Foundation

public struct VectorSearchResult: Sendable, Equatable {
    public let id: String
    public let score: Double
}

public protocol VectorIndexStore {
    func upsert(id: String, vector: [Float]) throws
    func search(query: [Float], topK: Int) throws -> [VectorSearchResult]
    func wipeAll() throws
}

/// Placeholder implementation used until FAISS Lite is integrated.
/// Persists encrypted index to disk so the storage/encryption contract is stable.
public final class EncryptedVectorIndexStore: VectorIndexStore {
    private struct IndexSnapshot: Codable {
        var dim: Int
        var items: [String: [Float]]
    }

    private let paths: AppPaths
    private let keychain: KeychainStore
    private let encryptedFiles: EncryptedFileStore
    private let crypto = AES256GCM()
    private let keyAccount = "faiss_dek_v1"

    private var snapshot: IndexSnapshot

    public init(paths: AppPaths, keychainService: String = "OfflineAgentCore.Store") throws {
        self.paths = paths
        self.keychain = KeychainStore(service: keychainService)
        self.encryptedFiles = EncryptedFileStore()
        self.snapshot = IndexSnapshot(dim: 0, items: [:])
        try loadIfPresent()
    }

    public func upsert(id: String, vector: [Float]) throws {
        if snapshot.dim == 0 { snapshot.dim = vector.count }
        if snapshot.dim != vector.count { return }
        snapshot.items[id] = vector
        try persist()
    }

    public func search(query: [Float], topK: Int) throws -> [VectorSearchResult] {
        guard snapshot.dim > 0, query.count == snapshot.dim else { return [] }
        var scored: [VectorSearchResult] = []
        scored.reserveCapacity(snapshot.items.count)
        for (id, v) in snapshot.items {
            let score = cosineSimilarity(a: query, b: v)
            scored.append(VectorSearchResult(id: id, score: score))
        }
        return scored
            .sorted(by: { $0.score > $1.score })
            .prefix(max(0, topK))
            .map { $0 }
    }

    public func wipeAll() throws {
        snapshot = IndexSnapshot(dim: 0, items: [:])
        try? encryptedFiles.delete(at: paths.encryptedVectorIndexURL)
        try? keychain.delete(account: keyAccount)
    }

    // MARK: - Persistence

    private func loadIfPresent() throws {
        guard let dek = try keychain.getData(account: keyAccount) else {
            // No key yet -> no index.
            return
        }
        guard let plaintext = try encryptedFiles.read(from: paths.encryptedVectorIndexURL, key: dek) else {
            return
        }
        let decoded = try JSONDecoder().decode(IndexSnapshot.self, from: plaintext)
        snapshot = decoded
    }

    private func persist() throws {
        let dek = try loadOrCreateDEK()
        let plaintext = try JSONEncoder().encode(snapshot)
        try encryptedFiles.write(
            plaintext: plaintext,
            to: paths.encryptedVectorIndexURL,
            key: dek,
            aad: Data("faiss_index_v1".utf8),
            fileProtection: .complete
        )
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

    // MARK: - Math

    private func cosineSimilarity(a: [Float], b: [Float]) -> Double {
        var dot: Double = 0
        var na: Double = 0
        var nb: Double = 0
        for i in 0..<a.count {
            let av = Double(a[i])
            let bv = Double(b[i])
            dot += av * bv
            na += av * av
            nb += bv * bv
        }
        let denom = (sqrt(na) * sqrt(nb))
        if denom == 0 { return 0 }
        return dot / denom
    }
}

