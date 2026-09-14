//
//  CachedAsyncImage.swift
//  zsignapp
//
//  Ảnh có bộ nhớ đệm 2 tầng và THU NHỎ về đúng cỡ hiển thị.
//
//  Vì sao không dùng AsyncImage của SwiftUI:
//    - Không có tầng đệm trong RAM: cuộn qua rồi cuộn lại là tải lại từ mạng.
//    - Không thu nhỏ: icon nguồn thường là PNG 512x512 hoặc 1024x1024 nhưng
//      chỉ hiển thị ở 56pt. Giải nén full-size tốn RAM gấp ~80 lần cần thiết
//      (1024x1024x4 byte = 4MB mỗi ảnh).
//
//  Ở đây: NSCache giữ ảnh ĐÃ thu nhỏ trong RAM, URLCache riêng giữ byte gốc
//  trên đĩa (256MB), ImageIO thu nhỏ ngay lúc giải mã nên không bao giờ
//  dựng bitmap full-size.
//

import SwiftUI
import UIKit
import ImageIO

final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 500
        memory.totalCostLimit = 64 * 1024 * 1024   // 64MB ảnh đã thu nhỏ

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "zsign-images"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    /// Ảnh đã có sẵn trong RAM (không chạm mạng, không chạm đĩa).
    func cached(_ url: URL, pixels: Int) -> UIImage? {
        memory.object(forKey: Self.key(url, pixels))
    }

    func image(for url: URL, pixels: Int) async -> UIImage? {
        let key = Self.key(url, pixels)
        if let hit = memory.object(forKey: key) { return hit }

        guard let data = try? await session.data(from: url).0,
              let image = Self.downsample(data, maxPixel: pixels)
        else { return nil }

        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key, cost: cost)
        return image
    }

    func clearMemory() { memory.removeAllObjects() }

    private static func key(_ url: URL, _ pixels: Int) -> NSString {
        "\(url.absoluteString)|\(pixels)" as NSString
    }

    /// Giải mã THẲNG ra ảnh nhỏ bằng ImageIO — không bao giờ dựng bitmap gốc.
    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - View

/// Thay thế AsyncImage. Dùng y như AsyncImage nhưng có đệm và thu nhỏ.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let size: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        let pixels = Int(size * displayScale)

        // Trúng RAM thì gán ngay trong cùng một khung hình, không nháy.
        if let hit = ImageCache.shared.cached(url, pixels: pixels) {
            image = hit
            return
        }
        image = nil
        let loaded = await ImageCache.shared.image(for: url, pixels: pixels)
        if !Task.isCancelled { image = loaded }
    }
}
