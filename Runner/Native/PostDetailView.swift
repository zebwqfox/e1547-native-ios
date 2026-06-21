import Photos
import SwiftUI
import UIKit

struct PostDetailView: View {
  @ObservedObject var model: PostsViewModel
  @ObservedObject var credentialStore: E621CredentialStore
  @ObservedObject var preferences: E621Preferences
  @ObservedObject var deepSeekSettings: DeepSeekSettings
  let onSearchTag: (String) -> Void

  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss

  @State private var currentPost: E621Post
  @State private var comments: [E621Comment] = []
  @State private var commentsPage = 1
  @State private var commentsCanLoadMore = true
  @State private var isLoadingComments = false
  @State private var commentsError: String?
  @State private var isDownloading = false
  @State private var isSavingToPhotos = false
  @State private var saveAlert: SaveAlert?
  @State private var shareItem: ShareItem?
  @State private var showsFullscreen = false
  @State private var translatedDescription: String?
  @State private var isTranslatingDescription = false
  @State private var translationError: String?
  @Namespace private var mediaNamespace

  private let client = E621APIClient()
  private let translator = DeepSeekTranslator()

  init(
    post: E621Post,
    model: PostsViewModel,
    credentialStore: E621CredentialStore,
    preferences: E621Preferences,
    deepSeekSettings: DeepSeekSettings,
    onSearchTag: @escaping (String) -> Void
  ) {
    _currentPost = State(initialValue: post)
    self.model = model
    self.credentialStore = credentialStore
    self.preferences = preferences
    self.deepSeekSettings = deepSeekSettings
    self.onSearchTag = onSearchTag
  }

  var body: some View {
    ZStack {
      detailContent
        .disabled(showsFullscreen)

      if showsFullscreen {
        FullscreenZoomOverlay(
          post: currentPost,
          preferences: preferences,
          namespace: mediaNamespace,
          geometryID: mediaGeometryID,
          onDismiss: dismissFullscreen
        )
        .zIndex(10)
        .transition(.opacity)
      }
    }
    .statusBarHidden(showsFullscreen)
    .toolbar(showsFullscreen ? .hidden : .visible, for: .navigationBar)
    .toolbar(showsFullscreen ? .hidden : .visible, for: .tabBar)
  }

  private var detailContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        media
        actions
        metadata
        if !currentPost.tagGroups.isEmpty {
          card {
            SectionHeader(title: "Tags", systemImage: "tag")
            ForEach(currentPost.tagGroups, id: \.title) { group in
              TagGroupView(
                title: group.title,
                color: tagCategoryColor(group.category),
                tags: group.tags,
                onSelect: searchTag
              )
            }
          }
        }
        commentsSection
      }
      .padding(.vertical, 16)
    }
    .id(currentPost.id)
    .background(Color(.systemGroupedBackground))
    .navigationTitle("#\(currentPost.id)")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: toggleFavorite) {
          Image(systemName: currentPost.isFavorited ? "heart.fill" : "heart")
        }
      }
    }
    .sheet(item: $shareItem) { item in
      ActivityView(activityItems: [item.url])
    }
    .alert(item: $saveAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .simultaneousGesture(detailPagingGesture)
    .task(id: currentPost.id) { loadComments(reset: true) }
  }

  // MARK: Sections

  @ViewBuilder
  private var media: some View {
    if currentPost.mediaType == .video {
      mediaContent
        .padding(.horizontal, 16)
    } else {
      mediaContent
        .matchedGeometryEffect(id: mediaGeometryID, in: mediaNamespace)
        .opacity(showsFullscreen ? 0 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: presentFullscreen)
        .padding(.horizontal, 16)
    }
  }

  @ViewBuilder
  private var mediaContent: some View {
    if currentPost.mediaType == .video, !currentPost.videoVariants.isEmpty {
      VideoPlayerView(
        variants: currentPost.videoVariants,
        preferences: preferences,
        aspectRatio: currentPost.displayAspectRatio
      )
    } else {
      PostMediaView(post: currentPost, preferences: preferences)
        .aspectRatio(currentPost.displayAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  private var mediaGeometryID: String { "post-media-\(currentPost.id)" }

  private enum DetailPageDirection {
    case previous
    case next
  }

  private var detailPagingGesture: some Gesture {
    DragGesture(minimumDistance: 48, coordinateSpace: .local)
      .onEnded { value in
        guard !showsFullscreen else { return }
        let width = value.translation.width
        let height = value.translation.height
        guard abs(width) > 90, abs(width) > abs(height) * 1.25 else { return }
        switchPost(width < 0 ? .next : .previous)
      }
  }

  private var actions: some View {
    card {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
        DetailActionButton(systemImage: currentPost.isFavorited ? "heart.fill" : "heart", title: "Favorite", isActive: currentPost.isFavorited, tint: .pink, action: toggleFavorite)
        DetailActionButton(systemImage: "arrow.up", title: "Up", isActive: currentPost.vote == 1, tint: .orange, action: { vote(upvote: true) })
        DetailActionButton(systemImage: "arrow.down", title: "Down", isActive: currentPost.vote == -1, tint: .blue, action: { vote(upvote: false) })
        DetailActionButton(systemImage: isSavingToPhotos ? "arrow.down.circle.dotted" : "photo.badge.arrow.down", title: "Save", isActive: isSavingToPhotos, tint: .green, action: saveToPhotos)
        DetailActionButton(systemImage: isDownloading ? "arrow.down.circle.dotted" : "square.and.arrow.up", title: "Share", isActive: isDownloading, tint: .mint, action: shareOriginal)
        DetailActionButton(systemImage: "safari", title: "Browser", isActive: false, tint: .cyan, action: openInBrowser)
        DetailActionButton(systemImage: "doc.on.doc", title: "Copy", isActive: false, tint: .purple, action: copyLink)
      }
    }
  }

  private var metadata: some View {
    card {
      RatingSummaryBadge(rating: currentPost.rating)
      Divider()
      InfoRow(label: "Score", systemImage: "arrow.up.arrow.down", value: "\(currentPost.score.total)")
      Divider()
      InfoRow(label: "Rating", systemImage: "shield", value: NSLocalizedString(currentPost.ratingTitle, comment: "post rating"))
      Divider()
      InfoRow(label: "Favorites", systemImage: "heart", value: "\(currentPost.favCount)")
      Divider()
      InfoRow(label: "Comments", systemImage: "text.bubble", value: "\(currentPost.commentCount)")
      if let width = currentPost.file.width, let height = currentPost.file.height {
        Divider()
        InfoRow(
          label: "Size",
          systemImage: "photo",
          value: "\(width) × \(height) \(currentPost.extTitle)\(currentPost.sizeTitle.map { " · \($0)" } ?? "")"
        )
      }
      if !currentPost.sources.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Label("Sources", systemImage: "link")
            .font(.subheadline.weight(.semibold))
          ForEach(currentPost.sources.prefix(6), id: \.self) { source in
            SourceLink(source: source)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !currentPost.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label("Description", systemImage: "text.alignleft")
              .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
              translateDescription()
            } label: {
              Label(isTranslatingDescription ? "Translating…" : "Translate", systemImage: "character.book.closed")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .disabled(isTranslatingDescription)
          }
          DTextView(currentPost.description)
          TranslationResultView(
            translatedText: translatedDescription,
            errorMessage: translationError
          )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var commentsSection: some View {
    card {
      HStack {
        SectionHeader(title: "Comments", systemImage: "text.bubble")
        Spacer()
        if currentPost.commentCount > 0 {
          Text("\(currentPost.commentCount)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }

      if let commentsError {
        Text(commentsError)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("Retry") {
          NativeHaptics.selection()
          loadComments(reset: true)
        }
          .buttonStyle(.bordered)
      } else if comments.isEmpty && isLoadingComments {
        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
      } else if comments.isEmpty {
        Text(currentPost.commentCount == 0 ? "No comments" : "No comments loaded")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ForEach(comments) { comment in
          CommentTile(comment: comment, deepSeekSettings: deepSeekSettings)
            .onAppear {
              if comment.id == comments.last?.id { loadComments(reset: false) }
            }
        }
        if isLoadingComments {
          ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
        } else if commentsCanLoadMore {
          Button("Load more") {
            NativeHaptics.selection()
            loadComments(reset: false)
          }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  // MARK: Card helper

  @ViewBuilder
  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      content()
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding(.horizontal, 16)
  }

  // MARK: Actions

  private func presentFullscreen() {
    guard !showsFullscreen else { return }
    NativeHaptics.impact(.light)
    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
      showsFullscreen = true
    }
  }

  private func dismissFullscreen() {
    NativeHaptics.impact(.soft)
    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
      showsFullscreen = false
    }
  }

  private func switchPost(_ direction: DetailPageDirection) {
    guard let currentIndex = model.posts.firstIndex(where: { $0.id == currentPost.id }) else { return }
    let targetIndex = currentIndex + (direction == .next ? 1 : -1)
    guard model.posts.indices.contains(targetIndex) else { return }

    let targetPost = model.posts[targetIndex]
    resetTransientPostState()
    NativeHaptics.selection()
    withAnimation(.easeInOut(duration: 0.18)) {
      currentPost = targetPost
    }
    model.loadMoreIfNeeded(current: targetPost)
  }

  private func resetTransientPostState() {
    comments = []
    commentsPage = 1
    commentsCanLoadMore = true
    commentsError = nil
    translatedDescription = nil
    isTranslatingDescription = false
    translationError = nil
    saveAlert = nil
    shareItem = nil
    showsFullscreen = false
  }

  private func toggleFavorite() {
    NativeHaptics.impact(currentPost.isFavorited ? .light : .medium)
    var updated = currentPost.withFavorite(!currentPost.isFavorited)
    if !currentPost.isFavorited, preferences.upvoteFavorites {
      updated = updated.withVote(upvote: true, replace: true)
    }
    model.toggleFavorite(currentPost)
    currentPost = updated
  }

  private func vote(upvote: Bool) {
    guard credentialStore.credentials.isComplete else {
      NativeHaptics.warning()
      model.needsCredentials = true
      return
    }
    NativeHaptics.selection()
    let updated = currentPost.withVote(upvote: upvote, replace: false)
    model.vote(currentPost, upvote: upvote)
    currentPost = updated
  }

  private func copyLink() {
    UIPasteboard.general.string = currentPost.webURL.absoluteString
    NativeHaptics.success()
  }

  private func openInBrowser() {
    NativeHaptics.selection()
    openURL(currentPost.webURL)
  }

  private func searchTag(_ tag: String) {
    NativeHaptics.selection()
    onSearchTag(tag)
    dismiss()
  }

  private func shareOriginal() {
    guard let url = currentPost.sourceURL, !isDownloading else { return }
    NativeHaptics.impact(.light)
    isDownloading = true
    Task {
      defer { isDownloading = false }
      do {
        let destination = try await downloadMedia(from: url)
        NativeHaptics.success()
        shareItem = ShareItem(url: destination)
      } catch {
        NativeHaptics.error()
        model.errorMessage = error.localizedDescription
      }
    }
  }

  private func saveToPhotos() {
    guard !isSavingToPhotos else { return }
    guard let url = photoLibraryURL else {
      NativeHaptics.warning()
      saveAlert = SaveAlert(
        title: NSLocalizedString("Could not save", comment: "save to photos failure title"),
        message: NSLocalizedString("This media format cannot be saved to Photos on iOS.", comment: "unsupported photos save format")
      )
      return
    }

    NativeHaptics.impact(.light)
    isSavingToPhotos = true
    Task {
      defer { isSavingToPhotos = false }
      do {
        let destination = try await downloadMedia(from: url)
        try await PhotoLibrarySaver.save(
          fileURL: destination,
          mediaType: currentPost.mediaType,
          albumTitle: "E1547"
        )
        saveAlert = SaveAlert(
          title: NSLocalizedString("Saved", comment: "save to photos success title"),
          message: NSLocalizedString("Saved to the E1547 album.", comment: "save to photos success message")
        )
        NativeHaptics.success()
      } catch {
        saveAlert = SaveAlert(
          title: NSLocalizedString("Could not save", comment: "save to photos failure title"),
          message: error.localizedDescription
        )
        NativeHaptics.error()
      }
    }
  }

  private var photoLibraryURL: URL? {
    switch currentPost.mediaType {
    case .video:
      return currentPost.videoURL
    case .gif:
      return currentPost.gifURL
    case .image:
      return currentPost.sourceURL
    }
  }

  private func downloadMedia(from url: URL) async throws -> URL {
    var request = URLRequest(url: url)
    request.setValue("e1547-native-mvp/1.0 (by binaryfloof)", forHTTPHeaderField: "User-Agent")
    let (temporaryURL, _) = try await URLSession.shared.download(for: request)
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(downloadName(for: url))
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
    return destination
  }

  private func downloadName(for url: URL) -> String {
    let urlExtension = url.pathExtension.isEmpty ? (currentPost.file.ext ?? "file") : url.pathExtension
    let base = (currentPost.downloadName as NSString).deletingPathExtension
    return "\(base).\(urlExtension)"
  }

  private func translateDescription() {
    guard !isTranslatingDescription else { return }
    NativeHaptics.impact(.light)
    isTranslatingDescription = true
    translationError = nil

    Task {
      defer { isTranslatingDescription = false }
      do {
        translatedDescription = try await translator.translateToChinese(
          DTextRenderer.plainText(from: currentPost.description),
          apiKey: deepSeekSettings.configuration.apiKey
        )
        NativeHaptics.success()
      } catch {
        translationError = error.localizedDescription
        NativeHaptics.error()
      }
    }
  }

  private func loadComments(reset: Bool) {
    guard credentialStore.credentials.isComplete else { return }
    guard !isLoadingComments else { return }
    if !reset, !commentsCanLoadMore { return }

    if reset {
      comments = []
      commentsPage = 1
      commentsCanLoadMore = true
      commentsError = nil
    }

    isLoadingComments = true
    Task {
      defer { isLoadingComments = false }
      do {
        let loaded = try await client.comments(
          postID: currentPost.id,
          page: commentsPage,
          credentials: credentialStore.credentials
        )
        comments = reset ? loaded : comments + loaded
        commentsPage += 1
        commentsCanLoadMore = !loaded.isEmpty
      } catch {
        commentsError = error.localizedDescription
      }
    }
  }
}

// MARK: - Subviews

struct SectionHeader: View {
  let title: LocalizedStringKey
  let systemImage: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.headline)
  }
}

/// A post source. http(s) sources become a tappable button labeled with the
/// recognized site (X, FurAffinity, Patreon, …); anything else is plain text.
struct SourceLink: View {
  let source: String

  @Environment(\.openURL) private var openURL

  var body: some View {
    if let url = URL(string: source), let scheme = url.scheme, scheme.hasPrefix("http") {
      Button {
        NativeHaptics.selection()
        openURL(url)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "link")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(siteName(for: url)))
              .font(.subheadline.weight(.medium))
            Text(source)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer()
          Image(systemName: "arrow.up.right")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
    } else {
      Text(source)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .textSelection(.enabled)
    }
  }

  private func siteName(for url: URL) -> String {
    let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "").lowercased()
    switch host {
    case let h where h.contains("x.com") || h.contains("twitter"): return "X (Twitter)"
    case let h where h.contains("furaffinity"): return "FurAffinity"
    case let h where h.contains("patreon"): return "Patreon"
    case let h where h.contains("deviantart"): return "DeviantArt"
    case let h where h.contains("inkbunny"): return "Inkbunny"
    case let h where h.contains("pixiv"): return "Pixiv"
    case let h where h.contains("e621") || h.contains("e926"): return "e621"
    case let h where h.contains("baraag"): return "Baraag"
    case let h where h.contains("newgrounds"): return "Newgrounds"
    case let h where h.contains("tumblr"): return "Tumblr"
    case let h where h.contains("bsky") || h.contains("bluesky"): return "Bluesky"
    default: return host.isEmpty ? "Open link" : host
    }
  }
}

struct InfoRow: View {
  let label: LocalizedStringKey
  let systemImage: String
  let value: String

  var body: some View {
    HStack {
      Label(label, systemImage: systemImage)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
  }
}

struct DetailActionButton: View {
  let systemImage: String
  let title: LocalizedStringKey
  let isActive: Bool
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.title3)
        Text(title)
          .font(.caption2)
      }
      .frame(maxWidth: .infinity)
      .foregroundStyle(isActive ? tint : Color.primary)
    }
    .buttonStyle(.plain)
  }
}

struct CommentTile: View {
  let comment: E621Comment
  @ObservedObject var deepSeekSettings: DeepSeekSettings

  @State private var translatedText: String?
  @State private var isTranslating = false
  @State private var translationError: String?

  private let translator = DeepSeekTranslator()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: "person.circle")
          .foregroundStyle(.secondary)
        Text(comment.creatorName)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Text(comment.displayDate)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Label("\(comment.score)", systemImage: "arrow.up.arrow.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if comment.isHidden {
          Image(systemName: "eye.slash").foregroundStyle(.red)
        }
      }
      DTextView(comment.body)
      HStack {
        Spacer()
        Button {
          translate()
        } label: {
          Label(isTranslating ? "Translating…" : "Translate", systemImage: "character.book.closed")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .disabled(isTranslating)
      }
      TranslationResultView(translatedText: translatedText, errorMessage: translationError)
      if let warningTitle = comment.warningTitle {
        Label(warningTitle, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func translate() {
    guard !isTranslating else { return }
    NativeHaptics.impact(.light)
    isTranslating = true
    translationError = nil

    Task {
      defer { isTranslating = false }
      do {
        translatedText = try await translator.translateToChinese(
          DTextRenderer.plainText(from: comment.body),
          apiKey: deepSeekSettings.configuration.apiKey
        )
        NativeHaptics.success()
      } catch {
        translationError = error.localizedDescription
        NativeHaptics.error()
      }
    }
  }
}

struct TranslationResultView: View {
  let translatedText: String?
  let errorMessage: String?

  var body: some View {
    if let translatedText, !translatedText.isEmpty {
      Text(translatedText)
        .font(.subheadline)
        .lineSpacing(3)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .textSelection(.enabled)
    }

    if let errorMessage, !errorMessage.isEmpty {
      Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
    }
  }
}

private struct FullscreenZoomOverlay: View {
  let post: E621Post
  @ObservedObject var preferences: E621Preferences
  let namespace: Namespace.ID
  let geometryID: String
  let onDismiss: () -> Void

  @State private var dragOffset: CGFloat = 0

  private var positiveDrag: CGFloat { max(0, dragOffset) }
  private var dragProgress: CGFloat { min(positiveDrag / 320, 1) }

  var body: some View {
    ZStack {
      Color.black
        .opacity(1 - dragProgress * 0.72)
        .ignoresSafeArea()

      fullscreenMedia
        .matchedGeometryEffect(id: geometryID, in: namespace)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: positiveDrag)
        .scaleEffect(1 - dragProgress * 0.14)
    }
    .ignoresSafeArea()
    .overlay(alignment: .topTrailing) {
      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(.white, .black.opacity(0.38))
          .padding(18)
      }
      .opacity(1 - dragProgress)
    }
    .contentShape(Rectangle())
    .simultaneousGesture(dismissGesture)
  }

  @ViewBuilder
  private var fullscreenMedia: some View {
    switch post.mediaType {
    case .video:
      if !post.videoVariants.isEmpty {
        VideoPlayerView(
          variants: post.videoVariants,
          preferences: preferences,
          aspectRatio: post.displayAspectRatio
        )
        .padding(.horizontal, 8)
      } else {
        unavailableMedia("Video unavailable")
      }
    case .gif:
      if let url = post.gifURL {
        ZoomableImage {
          AnimatedImageView(url: url)
            .aspectRatio(post.displayAspectRatio, contentMode: .fit)
        }
      } else {
        fullscreenImage
      }
    case .image:
      fullscreenImage
    }
  }

  private var fullscreenImage: some View {
    ZoomableImage {
      RemoteImageView(url: post.displayURL, contentMode: .fit, maxPixelSize: 2600)
        .aspectRatio(post.displayAspectRatio, contentMode: .fit)
    }
  }

  private var dismissGesture: some Gesture {
    DragGesture(minimumDistance: 12, coordinateSpace: .global)
      .onChanged { value in
        guard value.translation.height > 0 else { return }
        guard abs(value.translation.height) > abs(value.translation.width) * 0.7 else { return }
        dragOffset = value.translation.height
      }
      .onEnded { value in
        let shouldDismiss = value.translation.height > 80 || value.predictedEndTranslation.height > 170
        if shouldDismiss {
          onDismiss()
        } else {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            dragOffset = 0
          }
        }
      }
  }

  private func unavailableMedia(_ text: LocalizedStringKey) -> some View {
    VStack(spacing: 8) {
      Image(systemName: "play.slash")
        .font(.largeTitle)
      Text(text)
        .font(.subheadline)
    }
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// One tag category (Artist, Character, …) with a label and colored, tappable chips.
struct TagGroupView: View {
  let title: String
  let color: Color
  let tags: [String]
  let onSelect: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(LocalizedStringKey(title))
        .font(.caption2.weight(.bold))
        .foregroundStyle(color)
        .textCase(.uppercase)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
        ForEach(tags, id: \.self) { tag in
          Button {
            onSelect(tag)
          } label: {
            Text(tag.replacingOccurrences(of: "_", with: " "))
              .font(.caption)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
              .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct DTextView: View {
  private let text: String

  init(_ dtext: String) {
    text = DTextRenderer.plainText(from: dtext)
  }

  var body: some View {
    Text(text)
      .font(.subheadline)
      .lineSpacing(3)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

enum DTextRenderer {
  static func plainText(from dtext: String) -> String {
    var result = dtext
    let replacements = [
      #"\[/?(?:b|i|u|s|section|spoiler|quote|code|tn|table|tbody|tr|td|ul|ol|li|sup|sub)[^\]]*\]"#: "",
      #"\[br\]"#: "\n",
      #"\[hr\]"#: "\n\n",
      #""([^"]+)":(?:https?://\S+|/\S+)"#: "$1",
      #"\[(?:url|artist|post|user|wiki|pool|comment|forum|topic|dtext)[^\]]*\]([^\[]*)\[/[^\]]+\]"#: "$1",
    ]
    for (pattern, replacement) in replacements {
      result = result.replacing(pattern: pattern, with: replacement)
    }
    return result
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\n\n\n", with: "\n\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension String {
  func replacing(pattern: String, with replacement: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return self
    }
    let range = NSRange(startIndex..., in: self)
    return expression.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replacement)
  }
}

struct ShareItem: Identifiable {
  let id = UUID()
  let url: URL
}

struct SaveAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

enum PhotoLibrarySaveError: LocalizedError {
  case denied
  case unsupported
  case failed

  var errorDescription: String? {
    switch self {
    case .denied:
      return NSLocalizedString("Photos permission was denied.", comment: "photos permission denied")
    case .unsupported:
      return NSLocalizedString("This media format cannot be saved to Photos on iOS.", comment: "unsupported photos save format")
    case .failed:
      return NSLocalizedString("Photos could not save this file.", comment: "photos save failed")
    }
  }
}

enum PhotoLibrarySaver {
  static func save(fileURL: URL, mediaType: PostMediaType, albumTitle: String) async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized || status == .limited else {
      throw PhotoLibrarySaveError.denied
    }

    let album = fetchAlbum(named: albumTitle)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      PHPhotoLibrary.shared().performChanges {
        let assetRequest: PHAssetChangeRequest?
        switch mediaType {
        case .video:
          assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        case .image, .gif:
          assetRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }

        guard let placeholder = assetRequest?.placeholderForCreatedAsset else {
          return
        }

        let albumRequest: PHAssetCollectionChangeRequest?
        if let album {
          albumRequest = PHAssetCollectionChangeRequest(for: album)
        } else {
          albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
        }
        albumRequest?.addAssets([placeholder] as NSArray)
      } completionHandler: { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: PhotoLibrarySaveError.failed)
        }
      }
    }
  }

  private static func fetchAlbum(named title: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "localizedTitle = %@", title)
    return PHAssetCollection.fetchAssetCollections(
      with: .album,
      subtype: .albumRegular,
      options: options
    ).firstObject
  }
}

struct ActivityView: UIViewControllerRepresentable {
  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
