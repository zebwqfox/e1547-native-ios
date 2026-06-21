import Foundation

enum NativeTheme: String, CaseIterable, Identifiable {
  case system
  case light
  case dark
  case amoled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    case .amoled: return "AMOLED"
    }
  }
}

enum NativeGridQuilt: String, CaseIterable, Identifiable {
  case square
  case vertical

  var id: String { rawValue }

  var title: String {
    switch self {
    case .square: return "Square"
    case .vertical: return "Vertical"
    }
  }

  var description: String {
    switch self {
    case .square: return "tiles are quadratic"
    case .vertical: return "tiles expand vertically"
    }
  }
}

enum NativeVideoResolution: String, CaseIterable, Identifiable {
  case standard
  case high
  case full
  case ultra
  case source

  var id: String { rawValue }

  var title: String {
    switch self {
    case .standard: return "Standard (480p)"
    case .high: return "High (720p)"
    case .full: return "Full (1080p)"
    case .ultra: return "Ultra (4K)"
    case .source: return "Source"
    }
  }

  var pixels: Int {
    switch self {
    case .standard: return 640 * 480
    case .high: return 1280 * 720
    case .full: return 1920 * 1080
    case .ultra: return 3840 * 2160
    case .source: return 4096 * 2160
    }
  }
}

@MainActor
final class E621Preferences: ObservableObject {
  @Published var denylistText: String {
    didSet {
      defaults.set(denylistText, forKey: Keys.denylist)
    }
  }

  @Published var theme: NativeTheme {
    didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
  }

  @Published var tileSize: Double {
    didSet { defaults.set(tileSize, forKey: Keys.tileSize) }
  }

  @Published var quilt: NativeGridQuilt {
    didSet { defaults.set(quilt.rawValue, forKey: Keys.quilt) }
  }

  @Published var showPostInfo: Bool {
    didSet { defaults.set(showPostInfo, forKey: Keys.showPostInfo) }
  }

  @Published var upvoteFavorites: Bool {
    didSet { defaults.set(upvoteFavorites, forKey: Keys.upvoteFavorites) }
  }

  @Published var muteVideos: Bool {
    didSet { defaults.set(muteVideos, forKey: Keys.muteVideos) }
  }

  @Published var videoResolution: NativeVideoResolution {
    didSet { defaults.set(videoResolution.rawValue, forKey: Keys.videoResolution) }
  }

  @Published var incognitoKeyboard: Bool {
    didSet { defaults.set(incognitoKeyboard, forKey: Keys.incognitoKeyboard) }
  }

  @Published var appPin: String? {
    didSet {
      KeychainStorage.set(appPin ?? "", service: Keys.keychainService, account: Keys.appPin)
      if appPin == nil {
        biometricAuth = false
      }
    }
  }

  @Published var biometricAuth: Bool {
    didSet { defaults.set(biometricAuth, forKey: Keys.biometricAuth) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let storedDenylist = defaults.string(forKey: Keys.denylist) ?? ""
    let migratedDenylist = storedDenylist.trimmingCharacters(in: .whitespacesAndNewlines) == Self.legacyDefaultDenylist ? "" : storedDenylist
    denylistText = migratedDenylist
    if storedDenylist != migratedDenylist {
      defaults.set(migratedDenylist, forKey: Keys.denylist)
    }
    theme = NativeTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
    tileSize = defaults.object(forKey: Keys.tileSize) as? Double ?? 200
    quilt = NativeGridQuilt(rawValue: defaults.string(forKey: Keys.quilt) ?? "") ?? .square
    showPostInfo = defaults.object(forKey: Keys.showPostInfo) as? Bool ?? false
    upvoteFavorites = defaults.object(forKey: Keys.upvoteFavorites) as? Bool ?? false
    muteVideos = defaults.object(forKey: Keys.muteVideos) as? Bool ?? true
    videoResolution = NativeVideoResolution(rawValue: defaults.string(forKey: Keys.videoResolution) ?? "") ?? .source
    incognitoKeyboard = defaults.object(forKey: Keys.incognitoKeyboard) as? Bool ?? false
    appPin = KeychainStorage.get(service: Keys.keychainService, account: Keys.appPin)
    biometricAuth = defaults.object(forKey: Keys.biometricAuth) as? Bool ?? false
  }

  var denylist: [DenylistRule] {
    denylistText
      .split(whereSeparator: \.isNewline)
      .compactMap { DenylistRule(rawValue: String($0)) }
  }

  func allows(_ post: E621Post) -> Bool {
    !denylist.contains { $0.matches(post) }
  }

  private enum Keys {
    static let denylist = "native.e621.denylist"
    static let theme = "native.e621.theme"
    static let tileSize = "native.e621.tileSize"
    static let quilt = "native.e621.quilt"
    static let showPostInfo = "native.e621.showPostInfo"
    static let upvoteFavorites = "native.e621.upvoteFavorites"
    static let muteVideos = "native.e621.muteVideos"
    static let videoResolution = "native.e621.videoResolution"
    static let incognitoKeyboard = "native.e621.incognitoKeyboard"
    static let biometricAuth = "native.e621.biometricAuth"
    static let keychainService = "net.e1547.native.settings"
    static let appPin = "native.settings.appPin"
  }

  private static let legacyDefaultDenylist = """
young -rating:s
gore
scat
watersports
"""
}

struct DenylistRule: Equatable {
  let rawValue: String
  private let tokens: [String]

  init?(rawValue: String) {
    let cleaned = rawValue
      .split(separator: "#", maxSplits: 1)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !cleaned.isEmpty else { return nil }
    self.rawValue = cleaned
    tokens = cleaned
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  func matches(_ post: E621Post) -> Bool {
    var hasOptional = false
    var matchedOptional = false

    for token in tokens {
      var value = token
      var optional = false
      var inverted = false

      if value.first == "~" {
        optional = true
        value.removeFirst()
      }
      if value.first == "-" {
        inverted = true
        value.removeFirst()
      }

      guard !value.isEmpty else { continue }

      var matched = post.matchesDenylistToken(value)
      if inverted {
        matched.toggle()
      }

      if optional {
        hasOptional = true
        matchedOptional = matchedOptional || matched
      } else if !matched {
        return false
      }
    }

    return hasOptional ? matchedOptional : true
  }
}
