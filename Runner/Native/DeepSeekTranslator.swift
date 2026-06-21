import Foundation

struct DeepSeekConfiguration: Equatable {
  var apiKey: String

  var isComplete: Bool {
    !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

@MainActor
final class DeepSeekSettings: ObservableObject {
  @Published var configuration: DeepSeekConfiguration {
    didSet {
      KeychainStorage.set(configuration.apiKey, service: Keys.service, account: Keys.apiKey)
    }
  }

  init() {
    configuration = DeepSeekConfiguration(
      apiKey: KeychainStorage.get(service: Keys.service, account: Keys.apiKey) ?? ""
    )
  }

  private enum Keys {
    static let service = "net.e1547.native.deepseek"
    static let apiKey = "native.deepseek.apiKey"
  }
}

enum DeepSeekTranslationError: LocalizedError {
  case missingAPIKey
  case invalidResponse
  case server(status: Int, message: String?)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Enter your DeepSeek API key in Settings first."
    case .invalidResponse:
      return "DeepSeek did not return a readable translation."
    case .server(let status, let message):
      if let message, !message.isEmpty {
        return "DeepSeek returned \(status): \(message)"
      }
      return "DeepSeek returned status \(status)."
    }
  }
}

final class DeepSeekTranslator {
  static let model = "deepseek-v4-flash"

  private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func translateToChinese(_ text: String, apiKey: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw DeepSeekTranslationError.missingAPIKey
    }
    guard !trimmed.isEmpty else { return "" }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONEncoder().encode(
      DeepSeekChatRequest(
        model: Self.model,
        messages: [
          DeepSeekMessage(
            role: "system",
            content: "Translate e621 post descriptions, comments, and short UI text into natural Simplified Chinese. Preserve tag names, usernames, URLs, IDs, markdown/DText references, and line breaks. Return only the translation."
          ),
          DeepSeekMessage(role: "user", content: trimmed),
        ],
        temperature: 0.2
      )
    )

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw DeepSeekTranslationError.invalidResponse
    }
    guard 200..<300 ~= http.statusCode else {
      let message = try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data).error.message
      throw DeepSeekTranslationError.server(status: http.statusCode, message: message)
    }

    let decoded = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data)
    guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
          !content.isEmpty else {
      throw DeepSeekTranslationError.invalidResponse
    }
    return content
  }
}

private struct DeepSeekChatRequest: Encodable {
  let model: String
  let messages: [DeepSeekMessage]
  let temperature: Double
}

private struct DeepSeekMessage: Codable {
  let role: String
  let content: String
}

private struct DeepSeekChatResponse: Decodable {
  let choices: [Choice]

  struct Choice: Decodable {
    let message: DeepSeekMessage
  }
}

private struct DeepSeekErrorResponse: Decodable {
  let error: APIError

  struct APIError: Decodable {
    let message: String
  }
}
