import SwiftUI

/// A single thumbnail in the post grid: a cover-cropped portrait image with a
/// rating badge and a video/gif indicator. Styled for a standard native grid.
struct PostGridTile: View {
  let post: E621Post
  @ObservedObject var preferences: E621Preferences

  private var aspectRatio: CGFloat {
    switch preferences.quilt {
    case .square:
      return 1.0 / 1.2
    case .vertical:
      return post.displayAspectRatio
    }
  }

  var body: some View {
    Color.clear
      .aspectRatio(aspectRatio, contentMode: .fit)
      .overlay {
        RemoteImageView(url: post.thumbnailURL, contentMode: .fill, maxPixelSize: 400)
      }
      .overlay(alignment: .topLeading) {
        RatingBadge(rating: post.rating)
          .padding(7)
      }
      .overlay(alignment: .topTrailing) {
        if let badge = post.mediaBadge {
          Image(systemName: badge)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(5)
            .background(.black.opacity(0.35), in: Circle())
            .padding(5)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if post.isFavorited {
          Image(systemName: "heart.fill")
            .font(.caption)
            .foregroundColor(.pink)
            .padding(5)
            .background(.black.opacity(0.35), in: Circle())
            .padding(5)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if preferences.showPostInfo {
          PostTileInfoOverlay(post: post)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct PostTileInfoOverlay: View {
  let post: E621Post

  var body: some View {
    HStack(spacing: 8) {
      Label("\(post.score.total)", systemImage: "arrow.up.arrow.down")
      Label("\(post.favCount)", systemImage: "heart")
      if post.commentCount > 0 {
        Label("\(post.commentCount)", systemImage: "text.bubble")
      }
    }
    .font(.caption2.weight(.semibold))
    .labelStyle(.titleAndIcon)
    .foregroundStyle(.white)
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .background(.black.opacity(0.48), in: Capsule())
    .padding(6)
  }
}
