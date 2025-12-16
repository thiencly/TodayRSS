//
//  ImageDiskCache.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//

// FILE: Caching/ImageDiskCache.swift
// PURPOSE: On-disk + in-memory image cache actor
// SAFE TO EDIT: Yes, keep public API stable for CachedAsyncImage

import Foundation
import UIKit
import CryptoKit
import UniformTypeIdentifiers
import CoreImage

/// Holds image data with its dominant color
struct ImageWithColor {
    let image: UIImage
    let dominantColor: UIColor?
}

actor ImageDiskCache {
    static let shared = ImageDiskCache()
    private let fm = FileManager.default
    private let directory: URL
    private let memCache = NSCache<NSString, UIImage>()
    private var activeDownloads = 0
    private let maxConcurrentDownloads = 10  // Higher limit for faster preloading

    // Thread-safe synchronous access to memory cache
    private static let syncMemCache = NSCache<NSString, UIImage>()

    // Thread-safe synchronous access to color cache
    private static let syncColorCache = NSCache<NSString, UIColor>()

    // Dedicated session with aggressive timeout to prevent UI freezes
    private static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let maxCacheSizeMB: Int = 100 // Max 100MB of images
    private let maxCacheAgeDays: Int = 30 // Remove images older than 30 days

    init() {
        // Use a local FileManager to avoid capturing the actor-isolated property in nonisolated autoclosures.
        let localFM = FileManager.default
        let caches = localFM.urls(for: .cachesDirectory, in: .userDomainMask)
        let base: URL
        if let first = caches.first {
            base = first
        } else {
            base = localFM.temporaryDirectory
        }
        directory = base.appendingPathComponent("ImageCache", conformingTo: .directory)
        try? localFM.createDirectory(at: directory, withIntermediateDirectories: true)

        // Prune old/excess cache on init (in background)
        Task.detached(priority: .background) {
            await self.pruneCache()
        }
    }

    /// Removes old files and enforces size limit
    func pruneCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }

        let now = Date()
        let maxAge = TimeInterval(maxCacheAgeDays * 24 * 60 * 60)
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, date: Date, size: Int64)] = []

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modDate = values.contentModificationDate,
                  let size = values.fileSize else { continue }

            // Remove files older than maxAge
            if now.timeIntervalSince(modDate) > maxAge {
                try? fm.removeItem(at: file)
                continue
            }

            totalSize += Int64(size)
            fileInfos.append((file, modDate, Int64(size)))
        }

        // If still over size limit, remove oldest files
        let maxBytes = Int64(maxCacheSizeMB * 1024 * 1024)
        if totalSize > maxBytes {
            // Sort by date, oldest first
            fileInfos.sort { $0.date < $1.date }
            for info in fileInfos {
                if totalSize <= maxBytes { break }
                try? fm.removeItem(at: info.url)
                totalSize -= info.size
            }
        }
    }

    // Validate image has non-zero dimensions
    private func isValidImage(_ image: UIImage) -> Bool {
        return image.size.width > 0 && image.size.height > 0
    }

    // Force decode image off main thread to prevent lag during rendering
    // UIImage defers decoding until first render - this forces it early
    private func predecodedImage(_ image: UIImage, maxSize: CGFloat = 320) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        // Downsample to maxSize (default 320 for thumbnails, higher for full-screen)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Only downsample if image is larger than needed
        let scale: CGFloat
        if width > maxSize || height > maxSize {
            scale = min(maxSize / width, maxSize / height)
        } else {
            scale = 1.0
        }

        let newWidth = max(1, Int(width * scale))
        let newHeight = max(1, Int(height * scale))

        // Guard against invalid dimensions
        guard newWidth > 0, newHeight > 0 else { return image }

        // Create a bitmap context and draw - this forces decoding
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let decodedCGImage = context.makeImage() else {
            return image
        }

        return UIImage(cgImage: decodedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    func image(for url: URL) async -> UIImage? {
        let file = fileURL(for: url)
        let key = file.lastPathComponent as NSString

        // Check sync memory cache first (accessible from anywhere)
        // These are already predecoded
        if let syncCached = Self.syncMemCache.object(forKey: key), isValidImage(syncCached) {
            return syncCached
        }

        // Check actor-local memory cache
        if let cachedMem = memCache.object(forKey: key), isValidImage(cachedMem) {
            storeInSyncCache(cachedMem, for: url)
            return cachedMem
        }

        // Check disk cache (still fast, no network)
        if fm.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file),
           let rawImage = UIImage(data: data),
           isValidImage(rawImage) {
            // Predecode off main thread before caching
            let image = predecodedImage(rawImage)
            memCache.setObject(image, forKey: key)
            storeInSyncCache(image, for: url)
            return image
        }

        // Limit concurrent downloads to avoid overwhelming the network/main thread
        while activeDownloads >= maxConcurrentDownloads {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if Task.isCancelled { return nil }
        }

        activeDownloads += 1
        defer { activeDownloads -= 1 }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 4
            try Task.checkCancellation()
            let (data, response) = try await Self.imageSession.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let rawImage = UIImage(data: data), isValidImage(rawImage) {
                    // Save original data to disk
                    try? data.write(to: file, options: [.atomic])
                    // Predecode and downsample before caching in memory
                    let image = predecodedImage(rawImage)
                    memCache.setObject(image, forKey: key)
                    storeInSyncCache(image, for: url)
                    return image
                }
            }
        } catch {}
        return nil
    }

    /// Load high-resolution image for full-screen display (e.g., news reel)
    /// Uses larger maxSize (1200px) for better quality on large screens
    func highResImage(for url: URL) async -> UIImage? {
        let file = fileURL(for: url)

        // Check disk cache first
        if fm.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file),
           let rawImage = UIImage(data: data),
           isValidImage(rawImage) {
            // Use higher resolution for full-screen
            return predecodedImage(rawImage, maxSize: 1200)
        }

        // Limit concurrent downloads
        while activeDownloads >= maxConcurrentDownloads {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return nil }
        }

        activeDownloads += 1
        defer { activeDownloads -= 1 }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            try Task.checkCancellation()
            let (data, response) = try await Self.imageSession.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let rawImage = UIImage(data: data), isValidImage(rawImage) {
                    try? data.write(to: file, options: [.atomic])
                    return predecodedImage(rawImage, maxSize: 1200)
                }
            }
        } catch {}
        return nil
    }

    /// Get high-res image with its dominant color
    func highResImageWithColor(for url: URL) async -> ImageWithColor? {
        guard let image = await highResImage(for: url) else { return nil }

        let key = Self.cacheKey(for: url)

        // Check color cache first
        if let cachedColor = Self.syncColorCache.object(forKey: key) {
            return ImageWithColor(image: image, dominantColor: cachedColor)
        }

        // Extract color and cache it
        let color = extractDominantColor(from: image)
        if let color = color {
            Self.syncColorCache.setObject(color, forKey: key)
        }

        return ImageWithColor(image: image, dominantColor: color)
    }

    private func fileURL(for url: URL) -> URL {
        let name = sha256(url.absoluteString)
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheKey(for url: URL) -> NSString {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return (name + ".img") as NSString
    }

    /// Synchronous check for memory-cached image (no async, no actor isolation)
    nonisolated static func cachedImage(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        return syncMemCache.object(forKey: key)
    }

    /// Store image in the sync cache (called after loading)
    private func storeInSyncCache(_ image: UIImage, for url: URL) {
        let key = Self.cacheKey(for: url)
        Self.syncMemCache.setObject(image, forKey: key)
    }

    // MARK: - Dominant Color Extraction

    /// Get image with its dominant color
    func imageWithColor(for url: URL) async -> ImageWithColor? {
        guard let image = await image(for: url) else { return nil }

        let key = Self.cacheKey(for: url)

        // Check color cache first
        if let cachedColor = Self.syncColorCache.object(forKey: key) {
            return ImageWithColor(image: image, dominantColor: cachedColor)
        }

        // Extract color and cache it
        let color = extractDominantColor(from: image)
        if let color = color {
            Self.syncColorCache.setObject(color, forKey: key)
        }

        return ImageWithColor(image: image, dominantColor: color)
    }

    /// Synchronous check for cached dominant color
    nonisolated static func cachedColor(for url: URL) -> UIColor? {
        let key = cacheKey(for: url)
        return syncColorCache.object(forKey: key)
    }

    /// Extract dominant color from image using average color calculation (from bottom half)
    private func extractDominantColor(from image: UIImage) -> UIColor? {
        // Use CIImage for more reliable color extraction
        guard let ciImage = CIImage(image: image) else {
            return extractDominantColorFromCG(image)
        }

        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 else { return nil }

        // Sample from bottom half of image (where gradient will blend)
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

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Fallback color extraction using CGImage
    private func extractDominantColorFromCG(_ image: UIImage) -> UIColor? {
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

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
