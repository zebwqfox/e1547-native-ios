import SwiftUI
import AVKit
import ImageIO
import UniformTypeIdentifiers

let e621UserAgent = "e1547-native-mvp/1.0 (by binaryfloof)"

// MARK: - Post media switch

/// Renders a post's media according to its type: looping video, animated gif, or image.
struct PostMediaView: View {
  let post: E621Post
  @ObservedObject var preferences: E621Preferences

  var body: some View {
    switch post.mediaType {
    case .video:
      if !post.videoVariants.isEmpty {
        VideoPlayerView(variants: post.videoVariants, preferences: preferences)
      } else {
        // Rare webm posts ship no mp4 variant; AVFoundation can't play webm, so
        // show the static frame instead (Browser / Share still work).
        RemoteImageView(url: post.displayURL, contentMode: .fit, maxPixelSize: 1800)
          .overlay(alignment: .bottom) {
            Label("webm — open in browser to play", systemImage: "play.slash")
              .font(.caption2)
              .padding(6)
              .background(.black.opacity(0.5), in: Capsule())
              .foregroundStyle(.white)
              .padding(8)
          }
      }
    case .gif:
      if let url = post.gifURL {
        AnimatedImageView(url: url)
      } else {
        RemoteImageView(url: post.displayURL, contentMode: .fit, maxPixelSize: 1800)
      }
    case .image:
      RemoteImageView(url: post.displayURL, contentMode: .fit, maxPixelSize: 1800)
    }
  }
}

private struct UnsupportedMedia: View {
  let label: LocalizedStringKey
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "play.slash")
        .font(.largeTitle)
      Text(label)
        .font(.subheadline)
    }
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, minHeight: 160)
  }
}

// MARK: - Video

/// Looping AVPlayer video with native transport controls plus a resolution menu.
/// Uses mp4 variants (webm isn't playable by AVFoundation) and sends the e621
/// User-Agent. Switching resolution preserves playback position and play state.
struct VideoPlayerView: View {
  let variants: [PostVideoVariant]
  @ObservedObject var preferences: E621Preferences
  var aspectRatio: CGFloat? = nil

  @State private var player = AVPlayer()
  @State private var current: PostVideoVariant?
  @State private var endObserver: NSObjectProtocol?

  private var defaultVariant: PostVideoVariant? {
    variants.min { lhs, rhs in
      abs(lhs.pixelEstimate - preferences.videoResolution.pixels) < abs(rhs.pixelEstimate - preferences.videoResolution.pixels)
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      playerSurface
      if variants.count > 1 {
        resolutionMenu
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .onAppear {
      player.isMuted = preferences.muteVideos
      if current == nil, let variant = defaultVariant {
        load(variant, seekTo: .zero, autoplay: true)
      } else {
        player.play()
      }
    }
    .onChange(of: preferences.muteVideos) { _, muted in
      player.isMuted = muted
    }
    .onChange(of: preferences.videoResolution) { _, _ in
      guard let variant = defaultVariant, variant.id != current?.id else { return }
      load(variant, seekTo: player.currentTime(), autoplay: true)
    }
    .onDisappear { player.pause() }
  }

  // Keeping the resolution control below the player avoids overlapping AVKit's
  // own transport / AirPlay controls.
  @ViewBuilder
  private var playerSurface: some View {
    if let aspectRatio {
      VideoPlayer(player: player)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    } else {
      VideoPlayer(player: player)
    }
  }

  private var resolutionMenu: some View {
    Menu {
      ForEach(variants.reversed()) { variant in
        Button {
          if variant.id != current?.id { load(variant, seekTo: player.currentTime(), autoplay: true) }
        } label: {
          if variant.id == current?.id {
            Label(variant.label, systemImage: "checkmark")
          } else {
            Text(variant.label)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "rectangle.3.group")
        Text("Quality")
        Text(current?.label ?? "Auto").foregroundStyle(.secondary)
        Image(systemName: "chevron.down").font(.caption2)
      }
      .font(.caption.weight(.semibold))
    }
  }

  private func load(_ variant: PostVideoVariant, seekTo time: CMTime, autoplay: Bool) {
    let asset = AVURLAsset(
      url: variant.url,
      options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": e621UserAgent]]
    )
    let item = AVPlayerItem(asset: asset)
    player.replaceCurrentItem(with: item)
    current = variant

    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { _ in
      player.seek(to: .zero)
      player.play()
    }

    if time.isValid, time.seconds > 0 {
      player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
    }
    if autoplay { player.play() }
  }
}

// MARK: - Animated GIF

/// Loads and plays an animated GIF using ImageIO frame extraction.
struct AnimatedImageView: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> UIImageView {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.clipsToBounds = true
    context.coordinator.imageView = view
    context.coordinator.load(url)
    return view
  }

  func updateUIView(_ uiView: UIImageView, context: Context) {
    context.coordinator.imageView = uiView
    context.coordinator.load(url)
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor
  final class Coordinator {
    weak var imageView: UIImageView?
    private var loadedURL: URL?
    private var task: Task<Void, Never>?

    func load(_ url: URL) {
      guard loadedURL != url else { return }
      loadedURL = url
      task?.cancel()
      task = Task { [weak self] in
        var request = URLRequest(url: url)
        request.setValue(e621UserAgent, forHTTPHeaderField: "User-Agent")
        guard
          let (data, _) = try? await URLSession.shared.data(for: request),
          !Task.isCancelled
        else { return }
        let image = Self.animatedImage(from: data)
        await MainActor.run { self?.imageView?.image = image }
      }
    }

    private static func animatedImage(from data: Data) -> UIImage? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return UIImage(data: data)
      }
      let count = CGImageSourceGetCount(source)
      guard count > 1 else { return UIImage(data: data) }

      var frames: [UIImage] = []
      var duration: Double = 0
      for index in 0..<count {
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
        frames.append(UIImage(cgImage: cgImage))
        duration += frameDuration(source, index)
      }
      guard !frames.isEmpty else { return UIImage(data: data) }
      return UIImage.animatedImage(with: frames, duration: duration > 0 ? duration : Double(frames.count) / 24)
    }

    private static func frameDuration(_ source: CGImageSource, _ index: Int) -> Double {
      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
        let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      else { return 0.1 }
      let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
      let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
      let value = unclamped ?? clamped ?? 0.1
      return value < 0.02 ? 0.1 : value
    }
  }
}

// MARK: - Fullscreen viewer

/// A full-screen, dismissible viewer. Images are pinch/double-tap zoomable;
/// videos play with native controls.
struct FullscreenMediaView: View {
  let post: E621Post
  @ObservedObject var preferences: E621Preferences
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      switch post.mediaType {
      case .video:
        if !post.videoVariants.isEmpty {
          VideoPlayerView(variants: post.videoVariants, preferences: preferences)
        } else {
          UnsupportedMedia(label: "Video unavailable")
        }
      case .gif:
        if let url = post.gifURL {
          AnimatedImageView(url: url)
        } else {
          ZoomableImage { RemoteImageView(url: post.displayURL, contentMode: .fit, maxPixelSize: 2400) }
        }
      case .image:
        ZoomableImage { RemoteImageView(url: post.displayURL, contentMode: .fit, maxPixelSize: 2400) }
      }
    }
    .overlay(alignment: .topTrailing) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title)
          .foregroundStyle(.white, .black.opacity(0.4))
          .padding()
      }
    }
  }
}

private extension PostVideoVariant {
  var pixelEstimate: Int {
    // e621 variants expose height reliably; use a 16:9 estimate to match the
    // original Flutter setting, which chooses the closest pixel count.
    let width = Int((Double(height) * 16.0 / 9.0).rounded())
    return max(1, width * height)
  }
}

/// Pinch-to-zoom + double-tap-to-zoom + drag container for static content.
struct ZoomableImage<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  @State private var scale: CGFloat = 1
  @State private var offset: CGSize = .zero

  var body: some View {
    content
      .scaleEffect(scale)
      .offset(offset)
      .gesture(
        MagnifyGesture()
          .onChanged { scale = max(1, $0.magnification) }
          .onEnded { _ in if scale < 1.05 { reset() } }
      )
      .simultaneousGesture(
        DragGesture()
          .onChanged { if scale > 1 { offset = $0.translation } }
          .onEnded { _ in if scale <= 1 { offset = .zero } }
      )
      .onTapGesture(count: 2) {
        withAnimation(.spring) {
          if scale > 1 { reset() } else { scale = 2.5 }
        }
      }
  }

  private func reset() {
    withAnimation(.spring) {
      scale = 1
      offset = .zero
    }
  }
}
