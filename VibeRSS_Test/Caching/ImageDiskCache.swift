// FILE: Caching/ImageDiskCache.swift
// PURPOSE: On-disk + in-memory image cache actor
// SAFE TO EDIT: Yes, keep public API stable for CachedAsyncImage

import Foundation
import UIKit
import CryptoKit

actor ImageDiskCache {
    static let shared = ImageDiskCache()
    private let fm = FileManager.default
    private let directory: URL
    private let memCache = NSCache<NSString, UIImage>()

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
    }

    func image(for url: URL) async -> UIImage? {
        let file = fileURL(for: url)
        let key = file.lastPathComponent as NSString

        if let cachedMem = memCache.object(forKey: key) {
            return cachedMem
        }

        if fm.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file),
           let image = UIImage(data: data) {
            memCache.setObject(image, forKey: key)
            return image
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                try? data.write(to: file, options: [.atomic])
                if let image = UIImage(data: data) {
                    memCache.setObject(image, forKey: key)
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
}