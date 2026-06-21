import SwiftUI
import ImageIO

@MainActor
final class RemoteImageLoader: ObservableObject {
  @Published var image: UIImage?
  @Published var isLoading = false

  private static let cache = NSCache<NSString, UIImage>()
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.urlCache = URLCache(
      memoryCapacity: 96 * 1024 * 1024,
      diskCapacity: 512 * 1024 * 1024,
      diskPath: "e621-image-cache"
    )
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    return URLSession(configuration: configuration)
  }()
  private var task: Task<Void, Never>?

  func load(_ url: URL?, maxPixelSize: CGFloat?) {
    task?.cancel()
    image = nil
    guard let url = url else { return }
    let cacheKey = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)

    if let cached = Self.cache.object(forKey: cacheKey) {
      image = cached
      return
    }

    isLoading = true
    task = Task {
      defer { isLoading = false }
      do {
        var request = URLRequest(url: url)
        request.setValue("e1547-native-mvp/1.0 (by binaryfloof)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await Self.session.data(for: request)
        guard !Task.isCancelled, let loaded = Self.makeImage(from: data, maxPixelSize: maxPixelSize) else { return }
        Self.cache.setObject(loaded, forKey: cacheKey, cost: data.count)
        image = loaded
      } catch {
        if !Task.isCancelled {
          image = nil
        }
      }
    }
  }

  func cancel() {
    task?.cancel()
  }

  private static func makeImage(from data: Data, maxPixelSize: CGFloat?) -> UIImage? {
    guard let maxPixelSize, maxPixelSize > 0 else {
      return UIImage(data: data)
    }

    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
      return UIImage(data: data)
    }

    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
    ] as CFDictionary

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return UIImage(data: data)
    }
    return UIImage(cgImage: image)
  }

  private static func cacheKey(for url: URL, maxPixelSize: CGFloat?) -> NSString {
    let size = maxPixelSize.map { String(Int($0.rounded())) } ?? "original"
    return "\(url.absoluteString)#\(size)" as NSString
  }
}

struct RemoteImageView: View {
  let url: URL?
  let contentMode: ContentMode
  var maxPixelSize: CGFloat? = nil

  @StateObject private var loader = RemoteImageLoader()

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.white.opacity(0.10))

      if let image = loader.image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else if loader.isLoading {
        ProgressView()
      } else {
        Image(systemName: "photo")
          .font(.title2)
          .foregroundColor(.secondary)
      }
    }
    .clipped()
    .onAppear { loader.load(url, maxPixelSize: maxPixelSize) }
    .onChange(of: url) { _, value in loader.load(value, maxPixelSize: maxPixelSize) }
    .onDisappear { loader.cancel() }
  }
}
