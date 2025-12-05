//
//  iCloudSyncManager.swift
//  VibeRSS_Test
//
//  Manages iCloud key-value sync for feeds, folders, and settings
//

import Foundation
import Combine

@MainActor
final class iCloudSyncManager: ObservableObject {
    static let shared = iCloudSyncManager()

    // Keys for iCloud storage
    private enum Keys {
        static let feeds = "icloud.feeds"
        static let folders = "icloud.folders"
        static let heroSourceIDs = "icloud.heroSourceIDs"
        static let settings = "icloud.settings"
        static let lastModified = "icloud.lastModified"
    }

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?

    private init() {
        // Listen for iCloud changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )

        // Initial sync
        kvStore.synchronize()
    }

    // MARK: - External Change Handler

    @objc private func iCloudDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Data changed from another device or initial sync
            Task { @MainActor in
                NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)
            }
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("⚠️ iCloud: Quota exceeded")
        case NSUbiquitousKeyValueStoreAccountChange:
            print("ℹ️ iCloud: Account changed")
            Task { @MainActor in
                NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)
            }
        default:
            break
        }
    }

    // MARK: - Save Methods

    func saveFeeds(_ feeds: [Feed]) {
        do {
            let data = try JSONEncoder().encode(feeds)
            kvStore.set(data, forKey: Keys.feeds)
            kvStore.set(Date().timeIntervalSince1970, forKey: Keys.lastModified)
            kvStore.synchronize()
        } catch {
            print("⚠️ iCloud: Failed to save feeds: \(error)")
        }
    }

    func saveFolders(_ folders: [Folder]) {
        do {
            let data = try JSONEncoder().encode(folders)
            kvStore.set(data, forKey: Keys.folders)
            kvStore.set(Date().timeIntervalSince1970, forKey: Keys.lastModified)
            kvStore.synchronize()
        } catch {
            print("⚠️ iCloud: Failed to save folders: \(error)")
        }
    }

    func saveHeroSourceIDs(_ ids: [String]) {
        kvStore.set(ids, forKey: Keys.heroSourceIDs)
        kvStore.synchronize()
    }

    func saveSettings(_ settings: [String: Any]) {
        kvStore.set(settings, forKey: Keys.settings)
        kvStore.synchronize()
    }

    // MARK: - Load Methods

    func loadFeeds() -> [Feed]? {
        guard let data = kvStore.data(forKey: Keys.feeds) else { return nil }
        do {
            return try JSONDecoder().decode([Feed].self, from: data)
        } catch {
            print("⚠️ iCloud: Failed to load feeds: \(error)")
            return nil
        }
    }

    func loadFolders() -> [Folder]? {
        guard let data = kvStore.data(forKey: Keys.folders) else { return nil }
        do {
            return try JSONDecoder().decode([Folder].self, from: data)
        } catch {
            print("⚠️ iCloud: Failed to load folders: \(error)")
            return nil
        }
    }

    func loadHeroSourceIDs() -> [String]? {
        return kvStore.array(forKey: Keys.heroSourceIDs) as? [String]
    }

    func loadSettings() -> [String: Any]? {
        return kvStore.dictionary(forKey: Keys.settings)
    }

    func getLastModified() -> Date? {
        let timestamp = kvStore.double(forKey: Keys.lastModified)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    // MARK: - Merge Logic

    /// Merge local and cloud feeds, keeping unique entries
    func mergeFeeds(local: [Feed], cloud: [Feed]) -> [Feed] {
        var merged = local
        let localIDs = Set(local.map { $0.id })

        for cloudFeed in cloud {
            if !localIDs.contains(cloudFeed.id) {
                // Add feed from cloud that doesn't exist locally
                merged.append(cloudFeed)
            } else if let localIndex = merged.firstIndex(where: { $0.id == cloudFeed.id }) {
                // Update local feed with cloud data (cloud wins for same ID)
                merged[localIndex] = cloudFeed
            }
        }

        return merged
    }

    /// Merge local and cloud folders, keeping unique entries
    func mergeFolders(local: [Folder], cloud: [Folder]) -> [Folder] {
        var merged = local
        let localIDs = Set(local.map { $0.id })

        for cloudFolder in cloud {
            if !localIDs.contains(cloudFolder.id) {
                merged.append(cloudFolder)
            } else if let localIndex = merged.firstIndex(where: { $0.id == cloudFolder.id }) {
                // Update with cloud version
                merged[localIndex] = cloudFolder
            }
        }

        return merged
    }

    // MARK: - Force Sync

    func forceSync() {
        isSyncing = true
        kvStore.synchronize()
        lastSyncDate = Date()
        isSyncing = false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let iCloudDataDidChange = Notification.Name("iCloudDataDidChange")
}
