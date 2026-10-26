import Foundation
import Security

/// Секреты (ключ OpenAI) в Keychain как `kSecClassGenericPassword`, без сторонних библиотек.
/// Ошибки не роняют приложение: при сбое чтения ключ считается пустым, причина — в `ExplainRunner.shared.lastMessage`.
/// Само значение ключа никогда не попадает в сообщения.
enum KeychainStore {
    static let service = "home.ScreenExplain"
    static let openAIKeyAccount = "openAIKey"

    static func read(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            report("чтения", status)
            return nil
        }
    }

    /// Пустая строка удаляет запись.
    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return delete(account: account) }
        let data = Data(value.utf8)
        var status = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery(account)
            attributes[kSecValueData] = data
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            report("записи", status)
            return false
        }
        return true
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            report("удаления", status)
            return false
        }
        return true
    }

    private static func baseQuery(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private static func report(_ action: String, _ status: OSStatus) {
        let reason = (SecCopyErrorMessageString(status, nil) as String?) ?? "код \(status)"
        ExplainRunner.shared.lastMessage = "Keychain: ошибка \(action) ключа OpenAI (\(reason))"
    }
}
