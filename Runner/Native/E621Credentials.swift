import Foundation
import Security

struct E621Credentials: Equatable {
  var username: String
  var apiKey: String

  var isComplete: Bool {
    !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var authorizationHeader: String? {
    guard isComplete else { return nil }
    let value = "\(username):\(apiKey)"
    guard let data = value.data(using: .utf8) else { return nil }
    return "Basic \(data.base64EncodedString())"
  }
}

@MainActor
final class E621CredentialStore: ObservableObject {
  @Published var credentials: E621Credentials {
    didSet {
      defaults.set(credentials.username, forKey: Keys.username)
      KeychainStorage.set(credentials.apiKey, service: Keys.service, account: Keys.apiKey)
    }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    credentials = E621Credentials(
      username: defaults.string(forKey: Keys.username) ?? "",
      apiKey: KeychainStorage.get(service: Keys.service, account: Keys.apiKey) ?? ""
    )
  }

  private enum Keys {
    static let username = "native.e621.username"
    static let service = "net.e1547.native.e621"
    static let apiKey = "native.e621.apiKey"
  }
}

enum KeychainStorage {
  static func get(service: String, account: String) -> String? {
    var query = baseQuery(service: service, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func set(_ value: String, service: String, account: String) {
    var query = baseQuery(service: service, account: account)
    SecItemDelete(query as CFDictionary)

    guard let data = value.data(using: .utf8), !value.isEmpty else { return }
    query[kSecValueData as String] = data
    SecItemAdd(query as CFDictionary, nil)
  }

  private static func baseQuery(service: String, account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
  }
}
