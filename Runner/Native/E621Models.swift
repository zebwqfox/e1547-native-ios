import Foundation

struct E621PostsResponse: Decodable {
  let posts: [E621Post]
}

struct E621PostResponse: Decodable {
  let post: E621Post
}

struct E621Tag: Decodable, Identifiable, Equatable {
  let id: Int
  let name: String
  let postCount: Int
  let category: Int

  var displayName: String {
    name.replacingOccurrences(of: "_", with: " ")
  }

  var categoryTitle: String {
    switch category {
    case 0: return "General"
    case 1: return "Artist"
    case 3: return "Copyright"
    case 4: return "Character"
    case 5: return "Species"
    case 6: return "Invalid"
    case 7: return "Meta"
    case 8: return "Lore"
    default: return "Tag"
    }
  }
}

struct E621Post: Decodable, Identifiable, Equatable {
  let id: Int
  let file: E621File
  let preview: E621Preview
  let sample: E621Sample
  let score: E621Score
  let vote: Int?
  let tags: E621Tags
  let rating: String
  let favCount: Int
  let isFavorited: Bool
  let commentCount: Int
  let description: String
  let sources: [String]

  enum CodingKeys: String, CodingKey {
    case id
    case file
    case preview
    case sample
    case score
    case vote
    case tags
    case rating
    case favCount
    case isFavorited
    case commentCount
    case description
    case sources
  }

  init(
    id: Int,
    file: E621File,
    preview: E621Preview,
    sample: E621Sample,
    score: E621Score,
    vote: Int?,
    tags: E621Tags,
    rating: String,
    favCount: Int,
    isFavorited: Bool,
    commentCount: Int,
    description: String,
    sources: [String]
  ) {
    self.id = id
    self.file = file
    self.preview = preview
    self.sample = sample
    self.score = score
    self.vote = vote
    self.tags = tags
    self.rating = rating
    self.favCount = favCount
    self.isFavorited = isFavorited
    self.commentCount = commentCount
    self.description = description
    self.sources = sources
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    file = try container.decode(E621File.self, forKey: .file)
    preview = try container.decode(E621Preview.self, forKey: .preview)
    sample = try container.decode(E621Sample.self, forKey: .sample)
    score = try container.decode(E621Score.self, forKey: .score)
    vote = try container.decodeIfPresent(Int.self, forKey: .vote)
    tags = try container.decode(E621Tags.self, forKey: .tags)
    rating = try container.decode(String.self, forKey: .rating)
    favCount = try container.decodeIfPresent(Int.self, forKey: .favCount) ?? 0
    isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
    commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
  }

  var thumbnailURL: URL? {
    preview.url.flatMap(URL.init(string:))
  }

  var displayURL: URL? {
    sample.url.flatMap(URL.init(string:)) ?? file.url.flatMap(URL.init(string:))
  }

  var sourceURL: URL? {
    file.url.flatMap(URL.init(string:))
  }

  var webURL: URL {
    URL(string: "https://e621.net/posts/\(id)")!
  }

  var searchText: String {
    visibleTags.joined(separator: " ")
  }

  var allTags: Set<String> {
    Set(tags.general + tags.species + tags.character + tags.copyright + tags.artist + tags.invalid + tags.meta + (tags.lore ?? []))
  }

  var ratingTitle: String {
    switch rating {
    case "s": return "Safe"
    case "q": return "Questionable"
    case "e": return "Explicit"
    default: return rating.uppercased()
    }
  }

  var visibleTags: [String] {
    Array((tags.artist + tags.character + tags.copyright + tags.species + tags.general).prefix(32))
  }

  var extTitle: String {
    file.ext?.uppercased() ?? "FILE"
  }

  var sizeTitle: String? {
    guard let size = file.size else { return nil }
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(size))
  }

  func matchesDenylistToken(_ token: String) -> Bool {
    let normalized = token.lowercased()
    if normalized.contains(":") {
      let parts = normalized.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { return false }
      switch parts[0] {
      case "rating":
        return rating == parts[1] || ratingTitle.lowercased() == parts[1]
      case "type":
        return file.ext?.lowercased() == parts[1]
      case "id":
        return id == Int(parts[1])
      case "score":
        return score.total == Int(parts[1])
      default:
        return false
      }
    }
    return allTags.contains(normalized)
  }
}

struct E621File: Decodable, Equatable {
  let width: Int?
  let height: Int?
  let ext: String?
  let size: Int?
  let url: String?
}

struct E621Preview: Decodable, Equatable {
  let width: Int?
  let height: Int?
  let url: String?
}

struct E621Sample: Decodable, Equatable {
  let width: Int?
  let height: Int?
  let url: String?
  let alternates: E621SampleAlternates?
}

/// Video alternates under `sample.alternates`. `variants.mp4` is the full-res mp4,
/// `samples` holds downscaled mp4s (e.g. 480p / 720p). `original` (webm) and `has`
/// are intentionally ignored — AVFoundation can't play webm.
struct E621SampleAlternates: Decodable, Equatable {
  let variants: [String: E621VideoVariant]?
  let samples: [String: E621VideoVariant]?
}

struct E621VideoVariant: Decodable, Equatable {
  let width: Int?
  let height: Int?
  let url: String?
}

enum PostMediaType {
  case image
  case gif
  case video
}

/// A selectable video resolution for a post (e.g. "480p", "720p", "Full").
struct PostVideoVariant: Identifiable, Equatable {
  let id: String
  let label: String
  let height: Int
  let url: URL
}

struct E621Score: Decodable, Equatable {
  let up: Int?
  let down: Int?
  let total: Int
}

extension E621Post {
  func withFavorite(_ favorited: Bool) -> E621Post {
    let delta = favorited == isFavorited ? 0 : (favorited ? 1 : -1)
    return E621Post(
      id: id,
      file: file,
      preview: preview,
      sample: sample,
      score: score,
      vote: vote,
      tags: tags,
      rating: rating,
      favCount: max(0, favCount + delta),
      isFavorited: favorited,
      commentCount: commentCount,
      description: description,
      sources: sources
    )
  }

  func withVote(upvote: Bool, replace: Bool) -> E621Post {
    let current = vote ?? 0
    let target = upvote ? 1 : -1
    let result: (score: Int, vote: Int?)

    if current == target {
      result = replace ? (score.total, current) : (score.total - target, nil)
    } else if current == -target {
      result = (score.total + 2 * target, target)
    } else {
      result = (score.total + target, target)
    }

    return E621Post(
      id: id,
      file: file,
      preview: preview,
      sample: sample,
      score: E621Score(up: score.up, down: score.down, total: result.score),
      vote: result.vote,
      tags: tags,
      rating: rating,
      favCount: favCount,
      isFavorited: isFavorited,
      commentCount: commentCount,
      description: description,
      sources: sources
    )
  }

  var downloadName: String {
    let artists = tags.artist.filter { $0 != "conditional_dnp" && $0 != "unknown_artist" }
    let prefix = artists.isEmpty ? "" : "\(artists.joined(separator: ", ")) - "
    return "\(prefix)\(id).\(file.ext ?? "file")"
  }
}

extension E621Post {
  var mediaType: PostMediaType {
    switch file.ext?.lowercased() {
    case "webm", "mp4": return .video
    case "gif": return .gif
    default: return .image
    }
  }

  /// Best playable (mp4) URL for video posts. AVFoundation can't play webm, so we
  /// gather the mp4 variants/samples and prefer the largest one no taller than ~720p
  /// (to avoid downloading the full-res file), falling back to the smallest mp4.
  var videoURL: URL? {
    guard mediaType == .video else { return nil }

    var candidates: [(area: Int, height: Int, url: String)] = []
    func collect(_ variants: [String: E621VideoVariant]?) {
      for variant in variants?.values ?? [:].values {
        guard let url = variant.url, url.lowercased().hasSuffix(".mp4") else { continue }
        let height = variant.height ?? 0
        candidates.append(((variant.width ?? 0) * height, height, url))
      }
    }
    collect(sample.alternates?.variants)
    collect(sample.alternates?.samples)
    if let url = file.url, url.lowercased().hasSuffix(".mp4") {
      candidates.append((0, 0, url))
    }

    guard !candidates.isEmpty else { return nil }
    let mobileFriendly = candidates.filter { $0.height <= 820 }
    let chosen = mobileFriendly.max { $0.area < $1.area }
      ?? candidates.min { $0.area < $1.area }
    guard let urlString = chosen?.url else { return nil }
    return URL(string: urlString)
  }

  /// All playable (mp4) resolutions for a video post, lowest to highest, labeled
  /// with e621's own names (480p / 720p) plus "Full" for the full-res mp4.
  var videoVariants: [PostVideoVariant] {
    guard mediaType == .video else { return [] }
    var result: [PostVideoVariant] = []
    var seen = Set<String>()

    func add(label: String, _ variant: E621VideoVariant?) {
      guard
        let variant,
        let urlString = variant.url, urlString.lowercased().hasSuffix(".mp4"),
        let url = URL(string: urlString),
        !seen.contains(urlString)
      else { return }
      seen.insert(urlString)
      result.append(PostVideoVariant(id: urlString, label: label, height: variant.height ?? 0, url: url))
    }

    if let alternates = sample.alternates {
      for (key, variant) in alternates.samples ?? [:] { add(label: key, variant) }
      for (_, variant) in alternates.variants ?? [:] { add(label: "Full", variant) }
    }
    if let urlString = file.url, urlString.lowercased().hasSuffix(".mp4") {
      add(label: "Source", E621VideoVariant(width: file.width, height: file.height, url: urlString))
    }

    return result.sorted { $0.height < $1.height }
  }

  /// Original animated GIF URL for gif posts.
  var gifURL: URL? {
    guard mediaType == .gif else { return nil }
    return file.url.flatMap(URL.init(string:))
  }

  /// Tags grouped by category for display, in the order e621 uses, dropping empty groups.
  var tagGroups: [(title: String, category: Int, tags: [String])] {
    [
      ("Artist", 1, tags.artist),
      ("Copyright", 3, tags.copyright),
      ("Character", 4, tags.character),
      ("Species", 5, tags.species),
      ("General", 0, tags.general),
      ("Meta", 7, tags.meta),
      ("Lore", 8, tags.lore ?? []),
    ].filter { !$0.tags.isEmpty }
  }
}

struct E621Tags: Decodable, Equatable {
  let general: [String]
  let species: [String]
  let character: [String]
  let copyright: [String]
  let artist: [String]
  let invalid: [String]
  let meta: [String]
  let lore: [String]?
}

struct E621Comment: Decodable, Identifiable, Equatable {
  let id: Int
  let postId: Int
  let body: String
  let createdAt: String
  let updatedAt: String?
  let creatorId: Int
  let creatorName: String
  let score: Int
  let vote: Int?
  let warningType: String?
  let isHidden: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case postId
    case body
    case createdAt
    case updatedAt
    case creatorId
    case creatorName
    case score
    case vote
    case warningType
    case isHidden
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    postId = try container.decode(Int.self, forKey: .postId)
    body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
    createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    creatorId = try container.decode(Int.self, forKey: .creatorId)
    creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName) ?? "User #\(creatorId)"
    score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
    vote = try container.decodeIfPresent(Int.self, forKey: .vote)
    warningType = try container.decodeIfPresent(String.self, forKey: .warningType)
    isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
  }

  var displayDate: String {
    String(createdAt.prefix(10))
  }

  var warningTitle: String? {
    switch warningType {
    case "warning": return "User received a warning for this message"
    case "record": return "User received a record for this message"
    case "ban": return "User was banned for this message"
    case let value?: return value.capitalized
    case nil: return nil
    }
  }
}
