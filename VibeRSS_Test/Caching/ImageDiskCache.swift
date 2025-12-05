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

actor ImageDiskCache {
    static let shared = ImageDiskCache()
    private let fm = FileManager.default
    private let directory: URL
    private let memCache = NSCache<NSString, UIImage>()
    private var activeDownloads = 0
    private let maxConcurrentDownloads = 10  // Higher limit for faster preloading

    // Thread-safe synchronous access to memory cache
    private static let syncMemCache = NSCache<NSString, UIImage>()

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
    private func predecodedImage(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        // For thumbnails, downsample to 320x320 (4x for retina at 80pt display)
        // This reduces memory and rendering time for large source images
        let maxSize: CGFloat = 320
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
}
