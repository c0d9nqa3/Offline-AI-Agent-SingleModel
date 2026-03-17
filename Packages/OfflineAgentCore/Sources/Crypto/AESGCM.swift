import Foundation
import CryptoKit

public enum CryptoError: Error, LocalizedError {
    case invalidKeyLength
    case invalidCombinedData
    case encryptionFailed
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidKeyLength:
            return "密钥长度非法"
        case .invalidCombinedData:
            return "密文格式非法"
        case .encryptionFailed:
            return "加密失败"
        case .decryptionFailed:
            return "解密失败"
        }
    }
}

public struct AES256GCM: Sendable {
    public init() {}

    public func encrypt(plaintext: Data, key: Data, aad: Data? = nil) throws -> Data {
        guard key.count == 32 else { throw CryptoError.invalidKeyLength }
        let symmetricKey = SymmetricKey(data: key)

        let sealedBox: AES.GCM.SealedBox
        do {
            if let aad {
                sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, authenticating: aad)
            } else {
                sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
            }
        } catch {
            throw CryptoError.encryptionFailed
        }

        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    public func decrypt(combined: Data, key: Data, aad: Data? = nil) throws -> Data {
        guard key.count == 32 else { throw CryptoError.invalidKeyLength }
        let symmetricKey = SymmetricKey(data: key)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw CryptoError.invalidCombinedData
        }

        do {
            if let aad {
                return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: aad)
            } else {
                return try AES.GCM.open(sealedBox, using: symmetricKey)
            }
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}

