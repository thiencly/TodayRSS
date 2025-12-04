//
//  WidgetImageCache.swift
//  Shared image cache for widgets using App Group UserDefaults
//

import Foundation
import UIKit
import CryptoKit
import CoreImage

/// Shared image cache that stores compressed thumbnails in App Group UserDefaults
/// This approach avoids file system permission issues between app and widget
class WidgetImageCache {
    static let shared = WidgetImageCache()

    private let userDefaults: UserDefaults?
    private let cacheKey = "widgetThumbnailCache"
    private let maxCacheCount = 100 // Keep more thumbnails for multiple widgets
    private let maxImageDimension: CGFloat = 300 // Keep small for widgets
    private let queue = DispatchQueue(label: "com.viberss.widget.imagecache", qos: .userInitiated)

    private init() {
        userDefaults = UserDefaults(suiteName: appGroupIdentifier)
        if userDefaults == nil {
            print("WidgetImageCache: Failed to access App Group UserDefaults")
        }
    }

    // MARK: - Public API

    /// Save an image to the shared cache
    func saveImage(_ image: UIImage, for url: URL) {
        guard userDefaults != nil else { return }

        // Resize to widget-appropriate size
        let resized = resizeImage(image, maxDimension: maxImageDimension)

        // Compress heavily for UserDefaults storage
        guard let data = resized.jpegData(compressionQuality: 0.5) else { return }

        // Extract dominant color from bottom portion (where gradient will be)
        let dominantColorRGB = extractDominantColor(from: resized)

        let key = cacheKey(for: url)
        let newEntry = CachedImage(data: data, timestamp: Date(), dominantColorRGB: dominantColorRGB)

        // Use serial queue to prevent race conditions
        queue.sync {
            // Load existing cache
            var cache = loadCacheUnsafe()

            // Add new entry
            cache[key] = newEntry

            // Prune if over limit
            if cache.count > maxCacheCount {
                let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
                let toRemove = cache.count - maxCacheCount
                for (key, _) in sorted.prefix(toRemove) {
                    cache.removeValue(forKey: key)
                }
            }

            // Save back
            saveCacheUnsafe(cache)
        }
    }

    /// Load an image from the shared cache
    func loadImage(for url: URL) -> UIImage? {
        guard userDefaults != nil else { return nil }

        let key = cacheKey(for: url)

        return queue.sync {
            let cache = loadCacheUnsafe()
            guard let cached = cache[key],
                  let image = UIImage(data: cached.data) else {
                return nil
            }
            return image
        }
    }

    /// Load an image with its dominant color from the shared cache
    func loadImageWithColor(for url: URL) -> CachedImageData? {
        guard userDefaults != nil else { return nil }

        let key = cacheKey(for: url)

        return queue.sync {
            var cache = loadCacheUnsafe()

            guard let cached = cache[key],
                  let image = UIImage(data: cached.data) else {
                return nil
            }

            var dominantColor: UIColor? = nil
            if let rgb = cached.dominantColorRGB, rgb.count >= 3 {
                // Use cached color
                dominantColor = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1.0)
            } else {
                // Extract color on-the-fly for old cache entries and update cache
                if let rgb = extractDominantColor(from: image) {
                    dominantColor = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1.0)
                    // Update cache with the extracted color
                    cache[key] = CachedImage(data: cached.data, timestamp: cached.timestamp, dominantColorRGB: rgb)
                    saveCacheUnsafe(cache)
                }
            }

            return CachedImageData(image: image, dominantColor: dominantColor)
        }
    }

    /// Check if an image exists in cache
    func hasImage(for url: URL) -> Bool {
        let key = cacheKey(for: url)
        return queue.sync {
            let cache = loadCacheUnsafe()
            return cache[key] != nil
        }
    }

    /// Download and cache an image from URL
    func downloadAndCache(from url: URL) async -> Bool {
        // Skip SVG files - UIImage can't render them
        let pathLower = url.path.lowercased()
        if pathLower.hasSuffix(".svg") {
            print("WidgetImageCache: Skipping SVG \(url.lastPathComponent)")
            return false
        }

        // Skip if already cached AND the image is actually loadable
        // (hasImage only checks key exists, loadImage validates the data)
        if loadImage(for: url) != nil {
            return true
        }

        // Try up to 2 times for flaky CDNs (NYT, etc.)
        for attempt in 1...2 {
            if let image = await attemptDownload(from: url, attempt: attempt) {
                saveImage(image, for: url)
                print("WidgetImageCache: Cached \(Int(image.size.width))x\(Int(image.size.height)) from \(url.host ?? "unknown")")
                return true
            }

            // Wait before retry
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            }
        }

        return false
    }

    /// Single download attempt
    private func attemptDownload(from url: URL, attempt: Int) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            // Longer timeout for slow CDNs (NYT, etc.)
            request.timeoutInterval = attempt == 1 ? 15 : 20
            // Add headers to avoid blocks from CDNs
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("image/png,image/jpeg,image/webp,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            // Some CDNs require Referer header
            if let host = url.host {
                request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                if let httpResponse = response as? HTTPURLResponse {
                    if attempt == 2 {
                        print("WidgetImageCache: HTTP \(httpResponse.statusCode) for \(url.host ?? "unknown")")
                    }
                }
                return nil
            }

            // Check if response is SVG (some servers ignore Accept header)
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("svg") {
                print("WidgetImageCache: Server returned SVG for \(url.host ?? "unknown")")
                return nil
            }

            guard let image = UIImage(data: data) else {
                if attempt == 2 {
                    print("WidgetImageCache: Invalid image data from \(url.host ?? "unknown")")
                }
                return nil
            }

            return image
        } catch {
            if attempt == 2 {
                print("WidgetImageCache: Download failed for \(url.host ?? "unknown"): \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Clear all cached images
    func clearCache() {
        queue.sync {
            userDefaults?.removeObject(forKey: cacheKey)
        }
    }

    // MARK: - Private Helpers

    private struct CachedImage: Codable {
        let data: Data
        let timestamp: Date
        let dominantColorRGB: [CGFloat]? // [r, g, b] values 0-1
    }

    /// Represents cached image data with its dominant color
    struct CachedImageData {
        let image: UIImage
        let dominantColor: UIColor?
    }

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Thread-safe cache load (use from outside queue.sync blocks)
    private func loadCache() -> [String: CachedImage] {
        return queue.sync { loadCacheUnsafe() }
    }

    /// Thread-safe cache save (use from outside queue.sync blocks)
    private func saveCache(_ cache: [String: CachedImage]) {
        queue.sync { saveCacheUnsafe(cache) }
    }

    /// Internal load - only call from within queue.sync blocks
    private func loadCacheUnsafe() -> [String: CachedImage] {
        guard let userDefaults,
              let data = userDefaults.data(forKey: cacheKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: CachedImage].self, from: data)
        } catch {
            return [:]
        }
    }

    /// Internal save - only call from within queue.sync blocks
    private func saveCacheUnsafe(_ cache: [String: CachedImage]) {
        guard let userDefaults else { return }

        do {
            let data = try JSONEncoder().encode(cache)
            userDefaults.set(data, forKey: cacheKey)
        } catch {
            print("WidgetImageCache: Failed to save cache: \(error)")
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        // Don't upscale
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Extract dominant color from image using average color calculation
    private func extractDominantColor(from image: UIImage) -> [CGFloat]? {
        // Use CIImage for more reliable color extraction
        guard let ciImage = CIImage(image: image) else {
            // Fallback: try CGImage approach
            return extractDominantColorFromCG(image)
        }

        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 else { return nil }

        // Sample from bottom half of image
        let bottomHalf = ciImage.cropped(to: CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: extent.width,
            height: extent.height / 2
        ))

        // Use CIAreaAverage filter to get average color
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return extractDominantColorFromCG(image)
        }

        filter.setValue(bottomHalf, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: bottomHalf.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return extractDominantColorFromCG(image)
        }

        // Get the single pixel color
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0

        return [r, g, b]
    }

    /// Fallback color extraction using CGImage
    private func extractDominantColorFromCG(_ image: UIImage) -> [CGFloat]? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }

        // Scale down to 1x1 to get average color
        let bytesPerPixel = 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw entire image scaled to 1x1
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = CGFloat(pixelData[0]) / 255.0
        let g = CGFloat(pixelData[1]) / 255.0
        let b = CGFloat(pixelData[2]) / 255.0

        return [r, g, b]
    }
}
