import SwiftUI
import UIKit

extension Color {
  /// e621 signature amber/gold accent (#FCB328), used as the app-wide tint.
  static let e621Gold = Color(red: 0xFC / 255, green: 0xB3 / 255, blue: 0x28 / 255)
}

extension NativeTheme {
  var preferredColorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark, .amoled: return .dark
    }
  }
}

/// Rating colors matching the original app (s = safe, q = questionable, e = explicit).
func e621RatingColor(_ rating: String) -> Color {
  switch rating {
  case "s": return .green
  case "q": return .orange
  case "e": return .red
  default: return .gray
  }
}

extension E621Post {
  /// Aspect ratio (width / height) used to lay the full image out so it always fits
  /// the screen width. Clamped so extreme panoramas / very tall images don't blow up
  /// the layout; the image is shown with `.fit` so nothing is cropped.
  var displayAspectRatio: CGFloat {
    guard let width = file.width, let height = file.height, width > 0, height > 0 else {
      return 1
    }
    return min(max(CGFloat(width) / CGFloat(height), 0.6), 2.2)
  }

  /// SF Symbol shown on a grid thumbnail for non-image posts (video / gif).
  var mediaBadge: String? {
    switch file.ext?.lowercased() {
    case "webm", "mp4": return "play.fill"
    case "gif": return "square.stack.3d.down.right.fill"
    default: return nil
    }
  }
}

/// Category colors matching e621's tag categories.
func tagCategoryColor(_ category: Int) -> Color {
  switch category {
  case 1: return .orange
  case 3: return .purple
  case 4: return .green
  case 5: return .red
  case 6: return .gray
  case 7: return .yellow
  case 8: return .cyan
  default: return Color(.systemBlue)
  }
}

extension E621Tag {
  var categoryColor: Color { tagCategoryColor(category) }
}

extension Int {
  /// Compact count, e.g. 1.2k / 3.4m.
  var abbreviated: String {
    if self >= 1_000_000 { return String(format: "%.1fm", Double(self) / 1_000_000) }
    if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
    return String(self)
  }
}

/// A tag autocomplete suggestion row: category color bar, name + category, post count.
/// Mirrors the original app's autocomplete item.
struct TagSuggestionRow: View {
  let tag: E621Tag

  var body: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 2)
        .fill(tag.categoryColor)
        .frame(width: 4, height: 30)

      VStack(alignment: .leading, spacing: 1) {
        Text(tag.displayName)
          .lineLimit(1)
        Text(LocalizedStringKey(tag.categoryTitle))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Text(tag.postCount.abbreviated)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

/// Bold, high-visibility content-rating marker (S / Q / E).
struct RatingBadge: View {
  let rating: String
  var size: CGFloat = 34

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .fill(
          LinearGradient(
            colors: [e621RatingColor(rating), e621RatingColor(rating).opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .strokeBorder(.white.opacity(0.92), lineWidth: max(1.5, size * 0.07))

      Text(rating.uppercased())
        .font(.system(size: size * 0.62, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
    }
    .frame(width: size, height: size)
    .shadow(color: e621RatingColor(rating).opacity(0.45), radius: size * 0.22, x: 0, y: size * 0.08)
    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
  }
}

/// Large S/Q/E marker for detail pages.
struct RatingSummaryBadge: View {
  let rating: String

  var body: some View {
    HStack(spacing: 12) {
      RatingBadge(rating: rating, size: 46)
      VStack(alignment: .leading, spacing: 2) {
        Text("SQE Rating")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        Text(LocalizedStringKey(ratingTitle))
          .font(.headline.weight(.semibold))
      }
      Spacer()
    }
    .padding(12)
    .background(e621RatingColor(rating).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(e621RatingColor(rating).opacity(0.36), lineWidth: 1)
    )
  }

  private var ratingTitle: String {
    switch rating {
    case "s": return "Safe"
    case "q": return "Questionable"
    case "e": return "Explicit"
    default: return rating.uppercased()
    }
  }
}

/// Secure API key input with an explicit paste affordance.
struct PasteableAPIKeyField: View {
  let title: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: 8) {
      SecureField(title, text: $text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      Button {
        guard let pasted = UIPasteboard.general.string?
          .trimmingCharacters(in: .whitespacesAndNewlines),
          !pasted.isEmpty
        else { return }
        text = pasted
      } label: {
        Image(systemName: "doc.on.clipboard")
          .imageScale(.medium)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text("Paste API key"))
    }
  }
}
