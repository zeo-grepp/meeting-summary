import Foundation
import Security

/// API 키와 토큰이 사는 곳. UserDefaults는 `~/Library/Preferences`에 평문으로 남는다.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "MeetingAssistant"

    static func string(for key: String) -> String {
        var query = query(key)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
