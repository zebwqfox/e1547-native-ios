import Foundation

enum E621APIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case server(status: Int)
  case missingCredentials

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "The e621 URL could not be built."
    case .invalidResponse:
      return "The response from e621 could not be read."
    case .server(let status):
      return "e621 returned status \(status)."
    case .missingCredentials:
      return "Enter your e621 username and API key first."
    }
  }
}

final class E621APIClient {
  private let baseURL = URL(string: "https://e621.net")!
  private let session: URLSession

  init(session: URLSession = E621APIClient.makeSession()) {
    self.session = session
  }

  private static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.urlCache = URLCache(
      memoryCapacity: 64 * 1024 * 1024,
      diskCapacity: 256 * 1024 * 1024,
      diskPath: "e621-api-cache"
    )
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 60
    return URLSession(configuration: configuration)
  }

  func posts(
    tags: String,
    page: Int = 1,
    limit: Int = 40,
    credentials: E621Credentials
  ) async throws -> [E621Post] {
    var components = URLComponents(url: baseURL.appendingPathComponent("/posts.json"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "tags", value: tags),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components?.url else { throw E621APIError.invalidURL }

    let data = try await request(url, credentials: credentials)
    if let wrapped = try? JSONDecoder.e621.decode(E621PostsResponse.self, from: data) {
      return wrapped.posts
    }
    return try JSONDecoder.e621.decode([E621Post].self, from: data)
  }

  func hotPosts(page: Int = 1, limit: Int = 40, credentials: E621Credentials) async throws -> [E621Post] {
    try await posts(tags: "order:rank", page: page, limit: limit, credentials: credentials)
  }

  func tagAutocomplete(search: String, limit: Int = 10, credentials: E621Credentials) async throws -> [E621Tag] {
    var components = URLComponents(url: baseURL.appendingPathComponent("/tags/autocomplete.json"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "search[name_matches]", value: search),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components?.url else { throw E621APIError.invalidURL }

    let data = try await request(url, credentials: credentials)
    return Array(try JSONDecoder.e621.decode([E621Tag].self, from: data).prefix(limit))
  }

  func favorites(page: Int = 1, limit: Int = 40, credentials: E621Credentials) async throws -> [E621Post] {
    var components = URLComponents(url: baseURL.appendingPathComponent("/favorites.json"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components?.url else { throw E621APIError.invalidURL }

    let data = try await request(url, credentials: credentials)
    if let wrapped = try? JSONDecoder.e621.decode(E621PostsResponse.self, from: data) {
      return wrapped.posts
    }
    return try JSONDecoder.e621.decode([E621Post].self, from: data)
  }

  func setFavorite(_ post: E621Post, favorited: Bool, credentials: E621Credentials) async throws {
    if favorited {
      var components = URLComponents(url: baseURL.appendingPathComponent("/favorites.json"), resolvingAgainstBaseURL: false)
      components?.queryItems = [URLQueryItem(name: "post_id", value: String(post.id))]
      guard let url = components?.url else { throw E621APIError.invalidURL }
      _ = try await request(url, method: "POST", credentials: credentials)
    } else {
      let url = baseURL.appendingPathComponent("/favorites/\(post.id).json")
      _ = try await request(url, method: "DELETE", credentials: credentials)
    }
  }

  func vote(postID: Int, upvote: Bool, replace: Bool, credentials: E621Credentials) async throws {
    var components = URLComponents(url: baseURL.appendingPathComponent("/posts/\(postID)/votes.json"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "score", value: upvote ? "1" : "-1"),
      URLQueryItem(name: "no_unvote", value: replace ? "true" : "false"),
    ]
    guard let url = components?.url else { throw E621APIError.invalidURL }
    _ = try await request(url, method: "POST", credentials: credentials)
  }

  func post(id: Int, credentials: E621Credentials) async throws -> E621Post {
    let url = baseURL.appendingPathComponent("/posts/\(id).json")
    let data = try await request(url, credentials: credentials)
    if let wrapped = try? JSONDecoder.e621.decode(E621PostResponse.self, from: data) {
      return wrapped.post
    }
    return try JSONDecoder.e621.decode(E621Post.self, from: data)
  }

  func comments(postID: Int, page: Int = 1, limit: Int = 20, credentials: E621Credentials) async throws -> [E621Comment] {
    var components = URLComponents(url: baseURL.appendingPathComponent("/comments.json"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "group_by", value: "comment"),
      URLQueryItem(name: "search[post_id]", value: String(postID)),
      URLQueryItem(name: "search[order]", value: "id_desc"),
    ]
    guard let url = components?.url else { throw E621APIError.invalidURL }

    let data = try await request(url, credentials: credentials)
    return try JSONDecoder.e621.decode([E621Comment].self, from: data)
  }

  private func request(
    _ url: URL,
    method: String = "GET",
    credentials: E621Credentials
  ) async throws -> Data {
    guard credentials.isComplete else { throw E621APIError.missingCredentials }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("e1547-native-mvp/1.0 (by binaryfloof)", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authorization = credentials.authorizationHeader {
      request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw E621APIError.invalidResponse
    }
    guard 200..<300 ~= http.statusCode else {
      throw E621APIError.server(status: http.statusCode)
    }
    return data
  }
}

private extension JSONDecoder {
  static var e621: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}
