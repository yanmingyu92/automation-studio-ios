import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            "The saved Paperless token could not be read."
        case .unhandledStatus(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        }
    }
}

enum KeychainStore {
    private static let service = "com.automationstudio.dockeeper.paperless"
    private static let account = "api-token"

    static func savePaperlessToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attributes = [kSecValueData: data] as CFDictionary
            try check(SecItemUpdate(query as CFDictionary, attributes))
        } else if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func paperlessToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedData
        }
        return token
    }

    static func deletePaperlessToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainStoreError.unhandledStatus(status) }
    }
}
