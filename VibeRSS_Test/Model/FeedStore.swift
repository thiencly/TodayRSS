//
//  FeedStore.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


// FeedStore.swift
// Holds app persistence and in-memory state for feeds and folders.
// Responsibilities:
// - Load/save feeds and folders to UserDefaults (debounced)
// - Sync with iCloud for cross-device persistence
// - Assign/remove feeds to/from folders
// - Resolve and refresh favicon icons for feeds

import Foundation
import SwiftUI
import Combine
import WidgetKit

@MainActor
final class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = [] {
        didSet {
            debounceSaveFeeds()
            updateWidgetConfig()
        }
    }
    @Published var folders: [Folder] = [] {
        didSet {
            debounceSaveFolders()
            updateWidgetConfig()
        }
    }

    private let faviconService = FaviconService()
    private let key = "viberss.feeds"
    private let folderKey = "viberss.folders"
    private let iCloudSync = iCloudSyncManager.shared

    private var saveDebounceTask: Task<Void, Never>? = nil
    private var saveFoldersDebounceTask: Task<Void, Never>? = nil
    private var iCloudSyncTask: Task<Void, Never>? = nil
    private var isLoadingFromiCloud = false

    init() {
        load()
        loadFolders()

        // Try to merge with iCloud data
        mergeWithiCloud()

        if feeds.isEmpty {
            var initialFeeds: [Feed] = []

            if let url1 = URL(string: "https://www.theverge.com/rss/index.xml") {
                let icon1 = URL(string: "https://www.theverge.com/apple-touch-icon.png")
                initialFeeds.append(Feed(title: "The Verge", url: url1, iconURL: icon1))
            }
            if let url2 = URL(string: "https://www.macrumors.com/macrumors.xml") {
                let icon2 = URL(string: "https://cdn.macrumors.com/images-new/macrumors-og.png")
                initialFeeds.append(Feed(title: "MacRumors", url: url2, iconURL: icon2))
            }
            feeds = initialFeeds
        }

        // Listen for iCloud changes from other devices
        NotificationCenter.default.addObserver(
            forName: .iCloudDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleiCloudChange()
            }
        }

        // Immediately sync widget config on launch (not debounced)
        WidgetUpdater.shared.updateSourceConfig(feeds: feeds, folders: folders)
    }

    // MARK: - iCloud Sync

    private func mergeWithiCloud() {
        isLoadingFromiCloud = true
        defer { isLoadingFromiCloud = false }

        // Merge feeds
        if let cloudFeeds = iCloudSync.loadFeeds() {
            let merged = iCloudSync.mergeFeeds(local: feeds, cloud: cloudFeeds)
            if merged != feeds {
                feeds = merged
            }
        }

        // Merge folders
        if let cloudFolders = iCloudSync.loadFolders() {
            let merged = iCloudSync.mergeFolders(local: folders, cloud: cloudFolders)
            if merged != folders {
                folders = merged
            }
        }
    }

    private func handleiCloudChange() {
        mergeWithiCloud()
    }

    private func syncToiCloud() {
        iCloudSyncTask?.cancel()
        iCloudSyncTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            iCloudSync.saveFeeds(feeds)
            iCloudSync.saveFolders(folders)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(feeds)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Save error: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            feeds = try JSONDecoder().decode([Feed].self, from: data)
        } catch {
            print("Load error: \(error)")
        }
    }

    private func saveFolders() {
        do {
            let data = try JSONEncoder().encode(folders)
            UserDefaults.standard.set(data, forKey: folderKey)
        } catch {
            print("Save folders error: \(error)")
        }
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: folderKey) else { return }
        do {
            folders = try JSONDecoder().decode([Folder].self, from: data)
        } catch {
            print("Load folders error: \(error)")
        }
    }

    private func debounceSaveFeeds() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.save()
                if !self.isLoadingFromiCloud {
                    self.syncToiCloud()
                }
            }
        }
    }

    private func debounceSaveFolders() {
        saveFoldersDebounceTask?.cancel()
        saveFoldersDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.saveFolders()
                if !self.isLoadingFromiCloud {
                    self.syncToiCloud()
                }
            }
        }
    }

    func assign(_ feed: Feed, to folder: Folder?) {
        guard let idx = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[idx].folderID = folder?.id
    }

    func removeFolder(_ folder: Folder) {
        // Unassign any feeds in this folder
        for i in feeds.indices {
            if feeds[i].folderID == folder.id {
                feeds[i].folderID = nil
            }
        }
        // Remove the folder
        folders.removeAll { $0.id == folder.id }
    }

    func sources(in folder: Folder?) -> [Feed] {
        guard let folder else { return feeds }
        return feeds.filter { $0.folderID == folder.id }
    }

    func backfillIcons() {
        Task { [feeds] in
            for i in feeds.indices {
                if self.feeds[i].iconURL == nil {
                    if let icon = await faviconService.resolveIcon(for: self.feeds[i].url) {
                        self.feeds[i].iconURL = icon
                    }
                }
            }
        }
    }

    func refreshIcon(for feed: Feed) async {
        guard let idx = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        if let icon = await faviconService.resolveIcon(for: feed.url) {
            feeds[idx].iconURL = icon
        }
    }

    // MARK: - Widget Support

    private var widgetUpdateTask: Task<Void, Never>?

    private func updateWidgetConfig() {
        // Debounce widget updates
        widgetUpdateTask?.cancel()
        widgetUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            WidgetUpdater.shared.updateSourceConfig(feeds: feeds, folders: folders)
        }
    }
}
