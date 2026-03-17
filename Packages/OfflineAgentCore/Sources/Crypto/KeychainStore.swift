import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain错误：\(status)"
        case .invalidData:
            return "Keychain数据非法"
        }
    }
}

public struct KeychainStore: Sendable {
    public enum Accessibility: Sendable {
        case afterFirstUnlockThisDeviceOnly
    }

    private let service: String
    private let accessGroup: String?
    private let accessibility: Accessibility

    public init(
        service: String,
        accessGroup: String? = nil,
        accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    public func setData(_ data: Data, account: String) throws {
        var query: [String: Any] = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibilitySecAttr()

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = baseQuery(account: account) as CFDictionary
            let attributesToUpdate = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: accessibilitySecAttr(),
            ] as CFDictionary
            let updateStatus = SecItemUpdate(updateQuery, attributesToUpdate)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func getData(account: String) throws -> Data? {
        var query: [String: Any] = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = out as? Data else { throw KeychainError.invalidData }
        return data
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func accessibilitySecAttr() -> CFString {
        switch accessibility {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

