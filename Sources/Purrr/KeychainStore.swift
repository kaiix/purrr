import Foundation
import Security

enum KeychainStore {
  private static let service = "com.kaiix.purrr"

  static func string(for account: String) -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return value
  }

  static func set(_ value: String, for account: String) {
    let lookup: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    if value.isEmpty {
      SecItemDelete(lookup as CFDictionary)
      return
    }

    let data = Data(value.utf8)
    let attributes: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insert = lookup
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(insert as CFDictionary, nil)
    }
  }
}
