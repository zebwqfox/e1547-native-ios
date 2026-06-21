import Foundation

enum BrowseMode: String, CaseIterable, Identifiable {
  case search = "Search"
  case hot = "Hot"
  case favorites = "Favorites"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .search: return "magnifyingglass"
    case .hot: return "flame"
    case .favorites: return "heart"
    }
  }
}

@MainActor
final class PostsViewModel: ObservableObject {
  // Empty query = e621's default feed (latest posts), matching the original Home page.
  @Published var query = ""
  @Published var mode: BrowseMode = .search {
    didSet {
      guard oldValue != mode else { return }
      search()
    }
  }
  @Published private(set) var posts: [E621Post] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isMutatingFavorite = false
  @Published private(set) var hiddenCount = 0
  @Published private(set) var tagSuggestions: [E621Tag] = []
  @Published private(set) var isLoadingTagSuggestions = false
  @Published var errorMessage: String?
  @Published var needsCredentials = false
  @Published var showsSettings = false

  private let client = E621APIClient()
  private let credentialStore: E621CredentialStore
  private let preferences: E621Preferences
  private var page = 1
  private var canLoadMore = true
  private var tagSuggestionTask: Task<Void, Never>?

  init(credentialStore: E621CredentialStore, preferences: E621Preferences) {
    self.credentialStore = credentialStore
    self.preferences = preferences
    needsCredentials = !credentialStore.credentials.isComplete
  }

  func loadInitial() {
    guard posts.isEmpty else { return }
    search()
  }

  func search() {
    guard credentialStore.credentials.isComplete else {
      needsCredentials = true
      return
    }
    tagSuggestionTask?.cancel()
    tagSuggestions = []
    page = 1
    canLoadMore = true
    posts = []
    hiddenCount = 0
    errorMessage = nil
    Task { await loadPage(reset: true) }
  }

  func search(tag: String) {
    mode = .search
    query = tag
    search()
  }

  func queryDidChange() {
    tagSuggestionTask?.cancel()

    guard mode == .search, credentialStore.credentials.isComplete else {
      tagSuggestions = []
      return
    }

    let token = activeTagToken(in: query).raw
    guard token.count >= 3, !token.contains(":") else {
      tagSuggestions = []
      isLoadingTagSuggestions = false
      return
    }

    isLoadingTagSuggestions = true
    tagSuggestionTask = Task {
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled else { return }

      do {
        let loaded = try await client.tagAutocomplete(
          search: token,
          credentials: credentialStore.credentials
        )
        guard !Task.isCancelled else { return }
        tagSuggestions = loaded
      } catch {
        if !Task.isCancelled {
          tagSuggestions = []
        }
      }
      isLoadingTagSuggestions = false
    }
  }

  func useTagSuggestion(_ tag: E621Tag) {
    query = replacingActiveTagToken(in: query, with: tag.name)
    tagSuggestions = []
  }

  func loadMoreIfNeeded(current post: E621Post) {
    guard canLoadMore, posts.last?.id == post.id else { return }
    Task { await loadPage(reset: false) }
  }

  func refresh() async {
    page = 1
    canLoadMore = true
    await loadPage(reset: true)
  }

  func toggleFavorite(_ post: E621Post) {
    guard credentialStore.credentials.isComplete else {
      needsCredentials = true
      return
    }
    guard !isMutatingFavorite else { return }
    let target = !post.isFavorited

    updatePost(post.id) { current in
      var updated = current.withFavorite(target)
      if target, preferences.upvoteFavorites {
        updated = updated.withVote(upvote: true, replace: true)
      }
      return updated
    }

    isMutatingFavorite = true
    Task {
      defer { isMutatingFavorite = false }
      do {
        try await client.setFavorite(
          post,
          favorited: target,
          credentials: credentialStore.credentials
        )
        if target, preferences.upvoteFavorites {
          try? await client.vote(
            postID: post.id,
            upvote: true,
            replace: true,
            credentials: credentialStore.credentials
          )
        }
      } catch {
        replacePost(post)
        errorMessage = error.localizedDescription
      }
    }
  }

  func vote(_ post: E621Post, upvote: Bool) {
    guard credentialStore.credentials.isComplete else {
      needsCredentials = true
      return
    }

    let updated = post.withVote(upvote: upvote, replace: false)
    replacePost(updated)

    Task {
      do {
        try await client.vote(
          postID: post.id,
          upvote: upvote,
          replace: false,
          credentials: credentialStore.credentials
        )
      } catch {
        replacePost(post)
        errorMessage = error.localizedDescription
      }
    }
  }

  func replacePost(_ updated: E621Post) {
    updatePost(updated.id) { _ in updated }
  }

  private func loadPage(reset: Bool) async {
    guard !isLoading, canLoadMore else { return }
    guard credentialStore.credentials.isComplete else {
      needsCredentials = true
      return
    }
    isLoading = true
    defer { isLoading = false }

    do {
      let loaded: [E621Post]
      switch mode {
      case .search:
        loaded = try await client.posts(
          tags: query,
          page: page,
          credentials: credentialStore.credentials
        )
      case .hot:
        loaded = try await client.hotPosts(page: page, credentials: credentialStore.credentials)
      case .favorites:
        loaded = try await client.favorites(page: page, credentials: credentialStore.credentials)
      }
      let visible = loaded.filter(preferences.allows)
      hiddenCount = reset ? loaded.count - visible.count : hiddenCount + loaded.count - visible.count
      canLoadMore = !loaded.isEmpty
      page += 1
      posts = reset ? visible : posts + visible
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func updatePost(_ id: E621Post.ID, transform: (E621Post) -> E621Post) {
    posts = posts.map { post in
      post.id == id ? transform(post) : post
    }
  }

  private func activeTagToken(in text: String) -> (prefix: String, raw: String, suffix: String) {
    let end = text.endIndex
    guard let start = text[..<end].lastIndex(where: { $0.isWhitespace }) else {
      return ("", normalizedAutocompleteToken(text), "")
    }

    let prefix = String(text[...start])
    let raw = String(text[text.index(after: start)..<end])
    return (prefix, normalizedAutocompleteToken(raw), "")
  }

  private func replacingActiveTagToken(in text: String, with tag: String) -> String {
    let end = text.endIndex
    let start = text[..<end].lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
    let current = String(text[start..<end])
    let leading = current.prefix { $0 == "-" || $0 == "~" }
    let prefix = String(text[..<start])
    return "\(prefix)\(leading)\(tag) "
  }

  private func normalizedAutocompleteToken(_ token: String) -> String {
    String(token.drop { $0 == "-" || $0 == "~" })
  }
}
