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
    private let maxCacheCount = 30 // Keep only recent thumbnails
    private let maxImageDimension: CGFloat = 300 // Keep small for widgets

    private init() {
        userDefaults = UserDefaults(suiteName: appGroupIdentifier)
        if userDefaults == nil {
            print("WidgetImageCache: Failed to access App Group UserDefaults")
        }
    }

    // MARK: - Public API

    /// Save an image to the shared cache
    func saveImage(_ image: UIImage, for url: URL) {
        guard let userDefaults else { return }

        // Resize to widget-appropriate size
        let resized = resizeImage(image, maxDimension: maxImageDimension)

        // Compress heavily for UserDefaults storage
        guard let data = resized.jpegData(compressionQuality: 0.5) else { return }

        // Extract dominant color from bottom portion (where gradient will be)
        let dominantColorRGB = extractDominantColor(from: resized)

        // Load existing cache
        var cache = loadCache()

        // Add new entry
        let key = cacheKey(for: url)
        cache[key] = CachedImage(data: data, timestamp: Date(), dominantColorRGB: dominantColorRGB)

        // Prune if over limit
        if cache.count > maxCacheCount {
            let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = cache.count - maxCacheCount
            for (key, _) in sorted.prefix(toRemove) {
                cache.removeValue(forKey: key)
            }
        }

        // Save back
        saveCache(cache)
    }

    /// Load an image from the shared cache
    func loadImage(for url: URL) -> UIImage? {
        guard let userDefaults else { return nil }

        let cache = loadCache()
        let key = cacheKey(for: url)

        guard let cached = cache[key],
              let image = UIImage(data: cached.data) else {
            return nil
        }

        return image
    }

    /// Load an image with its dominant color from the shared cache
    func loadImageWithColor(for url: URL) -> CachedImageData? {
        guard userDefaults != nil else { return nil }

        var cache = loadCache()
        let key = cacheKey(for: url)

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
                saveCache(cache)
            }
        }

        return CachedImageData(image: image, dominantColor: dominantColor)
    }

    /// Check if an image exists in cache
    func hasImage(for url: URL) -> Bool {
        let cache = loadCache()
        return cache[cacheKey(for: url)] != nil
    }

    /// Download and cache an image from URL
    func downloadAndCache(from url: URL) async -> Bool {
        // Skip if already cached
        if hasImage(for: url) {
            return true
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return false
            }

            guard let image = UIImage(data: data) else {
                return false
            }

            saveImage(image, for: url)
            print("WidgetImageCache: Cached \(Int(image.size.width))x\(Int(image.size.height)) -> \(Int(maxImageDimension))px")
            return true
        } catch {
            print("WidgetImageCache: Download failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Clear all cached images
    func clearCache() {
        userDefaults?.removeObject(forKey: cacheKey)
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

    private func loadCache() -> [String: CachedImage] {
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

    private func saveCache(_ cache: [String: CachedImage]) {
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
