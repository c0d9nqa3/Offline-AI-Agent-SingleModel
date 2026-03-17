import Foundation

public struct EncryptedFileStore {
    private let crypto = AES256GCM()
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func write(
        plaintext: Data,
        to url: URL,
        key: Data,
        aad: Data? = nil,
        fileProtection: FileProtectionType = .complete
    ) throws {
        let ciphertext = try crypto.encrypt(plaintext: plaintext, key: key, aad: aad)

        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try ciphertext.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.protectionKey: fileProtection], ofItemAtPath: url.path)
    }

    public func read(
        from url: URL,
        key: Data,
        aad: Data? = nil
    ) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let ciphertext = try Data(contentsOf: url)
        return try crypto.decrypt(combined: ciphertext, key: key, aad: aad)
    }

    public func delete(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

