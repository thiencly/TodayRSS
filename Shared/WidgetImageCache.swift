//
//  WidgetImageCache.swift
//  File-based image cache for widgets using App Group container
//

import Foundation
import UIKit
import CryptoKit
import CoreImage

/// Shared image cache that stores thumbnails as files in the App Group container
/// This avoids UserDefaults size limits and allows larger caches
class WidgetImageCache {
    static let shared = WidgetImageCache()

    private let fileManager = FileManager.default
    private let cacheDirectoryName = "WidgetThumbnails"
    private let metadataFileName = "cache_metadata.json"
    private let maxCacheCount = 200 // Can store more with file-based storage
    private let maxImageDimension: CGFloat = 300 // Can use larger images now
    private let queue = DispatchQueue(label: "com.viberss.widget.imagecache", qos: .userInitiated)

    private var cacheDirectory: URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        return containerURL.appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    private var metadataURL: URL? {
        cacheDirectory?.appendingPathComponent(metadataFileName)
    }

    private init() {
        // Create cache directory if needed
        if let cacheDir = cacheDirectory {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        // Migrate from UserDefaults if needed (one-time)
        migrateFromUserDefaults()
    }

    // MARK: - Public API

    /// Save an image to the shared cache
    func saveImage(_ image: UIImage, for url: URL) {
        guard let cacheDir = cacheDirectory else { return }

        // Resize to widget-appropriate size
        let resized = resizeImage(image, maxDimension: maxImageDimension)

        // Compress for storage
        guard let data = resized.jpegData(compressionQuality: 0.6) else { return }

        // Extract dominant color
        let dominantColorRGB = extractDominantColor(from: resized)

        let key = cacheKey(for: url)
        let imageURL = cacheDir.appendingPathComponent("\(key).jpg")

        queue.async { [weak self] in
            guard let self else { return }

            // Write image file
            do {
                try data.write(to: imageURL)
            } catch {
                print("WidgetImageCache: Failed to write image: \(error)")
                return
            }

            // Update metadata
            var metadata = self.loadMetadata()
            metadata[key] = CacheEntry(timestamp: Date(), dominantColorRGB: dominantColorRGB)

            // Prune if over limit
            if metadata.count > self.maxCacheCount {
                self.pruneCache(metadata: &metadata, cacheDir: cacheDir)
            }

            self.saveMetadata(metadata)
        }
    }

    /// Load an image from the shared cache
    func loadImage(for url: URL) -> UIImage? {
        guard let cacheDir = cacheDirectory else { return nil }

        let key = cacheKey(for: url)
        let imageURL = cacheDir.appendingPathComponent("\(key).jpg")

        guard let data = try? Data(contentsOf: imageURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    /// Load an image with its dominant color from the shared cache
    func loadImageWithColor(for url: URL) -> CachedImageData? {
        guard let cacheDir = cacheDirectory else { return nil }

        let key = cacheKey(for: url)
        let imageURL = cacheDir.appendingPathComponent("\(key).jpg")

        guard let data = try? Data(contentsOf: imageURL),
              let image = UIImage(data: data) else {
            return nil
        }

        var dominantColor: UIColor? = nil
        let metadata = loadMetadata()

        if let entry = metadata[key], let rgb = entry.dominantColorRGB, rgb.count >= 3 {
            dominantColor = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1.0)
        } else {
            // Extract color on-the-fly for entries without color
            if let rgb = extractDominantColor(from: image) {
                dominantColor = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1.0)
                // Update metadata with extracted color
                queue.async { [weak self] in
                    var meta = self?.loadMetadata() ?? [:]
                    meta[key] = CacheEntry(timestamp: Date(), dominantColorRGB: rgb)
                    self?.saveMetadata(meta)
                }
            }
        }

        return CachedImageData(image: image, dominantColor: dominantColor)
    }

    /// Check if an image exists in cache
    func hasImage(for url: URL) -> Bool {
        guard let cacheDir = cacheDirectory else { return false }

        let key = cacheKey(for: url)
        let imageURL = cacheDir.appendingPathComponent("\(key).jpg")

        return fileManager.fileExists(atPath: imageURL.path)
    }

    /// Download and cache an image from URL
    func downloadAndCache(from url: URL) async -> Bool {
        // Skip SVG files
        let pathLower = url.path.lowercased()
        if pathLower.hasSuffix(".svg") {
            return false
        }

        // Skip if already cached
        if loadImage(for: url) != nil {
            return true
        }

        // Try up to 2 times
        for attempt in 1...2 {
            if let image = await attemptDownload(from: url, attempt: attempt) {
                saveImage(image, for: url)
                print("WidgetImageCache: Cached \(Int(image.size.width))x\(Int(image.size.height)) from \(url.host ?? "unknown")")
                return true
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        return false
    }

    /// Clear all cached images
    func clearCache() {
        guard let cacheDir = cacheDirectory else { return }

        queue.async { [weak self] in
            try? self?.fileManager.removeItem(at: cacheDir)
            try? self?.fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private Types

    private struct CacheEntry: Codable {
        let timestamp: Date
        let dominantColorRGB: [CGFloat]?
    }

    struct CachedImageData {
        let image: UIImage
        let dominantColor: UIColor?
    }

    // MARK: - Metadata Management

    private func loadMetadata() -> [String: CacheEntry] {
        guard let metadataURL = metadataURL,
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return [:]
        }
        return metadata
    }

    private func saveMetadata(_ metadata: [String: CacheEntry]) {
        guard let metadataURL = metadataURL else { return }

        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            print("WidgetImageCache: Failed to save metadata: \(error)")
        }
    }

    // MARK: - Cache Pruning

    private func pruneCache(metadata: inout [String: CacheEntry], cacheDir: URL) {
        // Sort by timestamp (oldest first)
        let sorted = metadata.sorted { $0.value.timestamp < $1.value.timestamp }
        let toRemove = metadata.count - maxCacheCount

        for (key, _) in sorted.prefix(toRemove) {
            let imageURL = cacheDir.appendingPathComponent("\(key).jpg")
            try? fileManager.removeItem(at: imageURL)
            metadata.removeValue(forKey: key)
        }

        print("WidgetImageCache: Pruned \(toRemove) images")
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaults() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
              userDefaults.data(forKey: "widgetThumbnailCache") != nil else {
            return
        }

        // Just remove the old cache - images will be re-downloaded as needed
        userDefaults.removeObject(forKey: "widgetThumbnailCache")
        print("WidgetImageCache: Migrated from UserDefaults (cleared old cache)")
    }

    // MARK: - Helper Methods

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

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

    private func attemptDownload(from url: URL, attempt: Int) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = attempt == 1 ? 15 : 20
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("image/png,image/jpeg,image/webp,image/*;q=0.8", forHTTPHeaderField: "Accept")

            if let host = url.host {
                request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("svg") {
                return nil
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func extractDominantColor(from image: UIImage) -> [CGFloat]? {
        guard let ciImage = CIImage(image: image) else {
            return extractDominantColorFromCG(image)
        }

        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 else { return nil }

        let bottomHalf = ciImage.cropped(to: CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: extent.width,
            height: extent.height / 2
        ))

        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return extractDominantColorFromCG(image)
        }

        filter.setValue(bottomHalf, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: bottomHalf.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return extractDominantColorFromCG(image)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        return [CGFloat(bitmap[0]) / 255.0, CGFloat(bitmap[1]) / 255.0, CGFloat(bitmap[2]) / 255.0]
    }

    private func extractDominantColorFromCG(_ image: UIImage) -> [CGFloat]? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }

        var pixelData = [UInt8](repeating: 0, count: 4)

        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return [CGFloat(pixelData[0]) / 255.0, CGFloat(pixelData[1]) / 255.0, CGFloat(pixelData[2]) / 255.0]
    }
}
