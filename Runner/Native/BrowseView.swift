import SwiftUI
import UIKit

/// Reusable paged post grid shared by the Browse and Favorites tabs.
struct PostGrid: View {
  @ObservedObject var model: PostsViewModel
  @ObservedObject var preferences: E621Preferences
  let credentialStore: E621CredentialStore
  @ObservedObject var deepSeekSettings: DeepSeekSettings
  let onSearchTag: (String) -> Void

  private var columns: [GridItem] {
    [GridItem(.adaptive(minimum: max(100, min(400, preferences.tileSize))), spacing: 6)]
  }

  var body: some View {
    content
      .refreshable { await model.refresh() }
      .alert(
        "Could not load posts",
        isPresented: Binding(
          get: { model.errorMessage != nil },
          set: { if !$0 { model.errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(model.errorMessage ?? "")
      }
      .sheet(isPresented: $model.needsCredentials) {
        CredentialsView(store: credentialStore) {
          model.needsCredentials = false
          model.search()
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    if model.posts.isEmpty && model.isLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.posts.isEmpty {
      ContentUnavailableView(
        "No posts",
        systemImage: "square.grid.2x2",
        description: Text("Pull to refresh or try a different search.")
      )
    } else {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 6) {
          ForEach(model.posts) { post in
            NavigationLink {
              PostDetailView(
                post: post,
                model: model,
                credentialStore: credentialStore,
                preferences: preferences,
                deepSeekSettings: deepSeekSettings,
                onSearchTag: onSearchTag
              )
            } label: {
              PostGridTile(post: post, preferences: preferences)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.selection() })
            .contextMenu {
              Button {
                NativeHaptics.impact(post.isFavorited ? .light : .medium)
                model.toggleFavorite(post)
              } label: {
                Label(
                  post.isFavorited ? "Unfavorite" : "Favorite",
                  systemImage: post.isFavorited ? "heart.slash" : "heart"
                )
              }
              Button {
                UIPasteboard.general.string = post.webURL.absoluteString
                NativeHaptics.success()
              } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
              }
            }
            .onAppear { model.loadMoreIfNeeded(current: post) }
          }
        }
        .padding(.horizontal, 6)

        if model.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding()
        }
      }
    }
  }
}

/// Browse tab: a popular feed plus tag search via the native search bar.
struct BrowseView: View {
  @ObservedObject var model: PostsViewModel
  @ObservedObject var preferences: E621Preferences
  let credentialStore: E621CredentialStore
  @ObservedObject var deepSeekSettings: DeepSeekSettings
  let onSearchTag: (String) -> Void
  @State private var didInitialize = false

  private var browseTitle: String {
    switch model.mode {
    case .hot: return "Popular"
    case .search: return model.query.trimmingCharacters(in: .whitespaces).isEmpty ? "Posts" : "Search"
    case .favorites: return "Posts"
    }
  }

  var body: some View {
    NavigationStack {
      PostGrid(
        model: model,
        preferences: preferences,
        credentialStore: credentialStore,
        deepSeekSettings: deepSeekSettings,
        onSearchTag: onSearchTag
      )
        .navigationTitle(LocalizedStringKey(browseTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button {
                model.mode = .hot
              } label: {
                Label("Popular", systemImage: "flame")
              }
              Button {
                model.mode = .search
                model.search()
              } label: {
                Label("Search current tags", systemImage: "magnifyingglass")
              }
              Divider()
              Button {
                model.search()
              } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
        .searchable(
          text: $model.query,
          placement: .navigationBarDrawer(displayMode: .always),
          prompt: "tags  ·  e.g. score:>=20 order:score"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .searchSuggestions {
          if model.isLoadingTagSuggestions && model.tagSuggestions.isEmpty {
            HStack(spacing: 10) {
              ProgressView()
              Text("Searching tags…").foregroundStyle(.secondary)
            }
          }
          ForEach(model.tagSuggestions) { tag in
            Button {
              model.useTagSuggestion(tag)
            } label: {
              TagSuggestionRow(tag: tag)
            }
          }
        }
        .onChange(of: model.query) { _, _ in model.queryDidChange() }
        .onSubmit(of: .search) {
          model.mode = .search
          model.search()
        }
        .onAppear {
          // Load the default feed (empty tags = latest, like the original Home) only
          // once, so returning from a tag-search in the detail page doesn't clobber it.
          if !didInitialize {
            didInitialize = true
            model.loadInitial()
          }
        }
    }
  }
}

/// Favorites tab: the signed-in user's favorited posts.
struct FavoritesView: View {
  @ObservedObject var model: PostsViewModel
  @ObservedObject var preferences: E621Preferences
  let credentialStore: E621CredentialStore
  @ObservedObject var deepSeekSettings: DeepSeekSettings
  let onSearchTag: (String) -> Void

  var body: some View {
    NavigationStack {
      PostGrid(
        model: model,
        preferences: preferences,
        credentialStore: credentialStore,
        deepSeekSettings: deepSeekSettings,
        onSearchTag: onSearchTag
      )
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
          if model.mode != .favorites {
            model.mode = .favorites
          } else {
            model.loadInitial()
          }
        }
    }
  }
}
