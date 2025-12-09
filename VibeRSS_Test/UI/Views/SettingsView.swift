import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("heroCollapsedOnLaunch") private var heroCollapsedOnLaunch: Bool = false
    @AppStorage("showLatestView") private var showLatestView: Bool = true
    @AppStorage("showTodayView") private var showTodayView: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Bindable private var syncManager = BackgroundSyncManager.shared
    @State private var showOnboarding = false
    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    @State private var currentAppIcon: AppIconOption = .automatic

    enum AppIconOption: String, CaseIterable {
        case automatic = "Automatic"
        case light = "Light"
        case dark = "Dark"

        var iconName: String? {
            switch self {
            case .automatic: return nil // Use default
            case .light: return "AppIconLight"
            case .dark: return "AppIconDark"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Background Refresh Warning
                if backgroundRefreshStatus != .available {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Background Refresh Disabled")
                                    .font(.subheadline.weight(.semibold))
                                Text("Widgets won't update automatically. Enable Background App Refresh in Settings → General → Background App Refresh.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                // MARK: - Background Sync Section
                Section {
                    Picker("Sync Interval", selection: $syncManager.syncInterval) {
                        ForEach(BackgroundSyncManager.SyncInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }

                    if let lastSync = syncManager.lastSyncDate {
                        HStack {
                            Text("Last Synced")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task {
                            await syncManager.syncNow()
                        }
                    } label: {
                        HStack {
                            Text("Sync Now")
                            Spacer()
                            if syncManager.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(syncManager.isSyncing)

                    Button {
                        Task {
                            // Clear widget image cache and re-sync to get fresh colors
                            WidgetImageCache.shared.clearCache()
                            await syncManager.syncNow()
                        }
                    } label: {
                        Text("Refresh Widget Images")
                    }
                    .disabled(syncManager.isSyncing)

                    Button(role: .destructive) {
                        Task {
                            // Clear all widget data and resync
                            WidgetImageCache.shared.clearCache()
                            WidgetDataManager.shared.clearAllData()
                            await syncManager.syncNow()
                        }
                    } label: {
                        Text("Reset Widget Data")
                    }
                    .disabled(syncManager.isSyncing)
                } header: {
                    Text("Background Sync")
                } footer: {
                    Text("Background sync keeps your feeds and widgets updated automatically. Use 'Reset Widget Data' if widgets show incorrect articles.")
                }

                // MARK: - Highlights Section
                Section {
                    Toggle("Collapse Highlights on Launch", isOn: $heroCollapsedOnLaunch)
                } header: {
                    Text("Highlights")
                } footer: {
                    Text("When enabled, the Today Highlights section will start collapsed when you open the app.")
                }

                // MARK: - Sidebar Section
                Section {
                    Toggle("Show Latest", isOn: $showLatestView)
                    Toggle("Show Today", isOn: $showTodayView)
                } header: {
                    Text("Sidebar")
                } footer: {
                    Text("Choose which views appear in the sidebar. Latest shows the newest article from each source. Today shows all articles from the past 24 hours.")
                }

                // MARK: - App Icon Section
                Section {
                    Picker("App Icon", selection: $currentAppIcon) {
                        ForEach(AppIconOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .onChange(of: currentAppIcon) { _, newValue in
                        setAppIcon(newValue)
                    }
                } header: {
                    Text("App Icon")
                } footer: {
                    Text("Automatic follows your device's appearance. Choose Light or Dark to always use that icon.")
                }

                // MARK: - iCloud Sync Section
                Section {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud.fill")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    if let lastSync = iCloudSyncManager.shared.getLastModified() {
                        HStack {
                            Text("Last Synced")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        iCloudSyncManager.shared.forceSync()
                    } label: {
                        Text("Sync Now")
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Your feeds, folders, and highlight sources are automatically synced across all your devices using iCloud.")
                }

                // MARK: - About Section
                Section {
                    Button {
                        showOnboarding = true
                    } label: {
                        HStack {
                            Label("Show Onboarding", systemImage: "hand.wave.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("About")
                } footer: {
                    Text("View the welcome tutorial again.")
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
            }
            .onAppear {
                backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
                loadCurrentAppIcon()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func loadCurrentAppIcon() {
        let currentIconName = UIApplication.shared.alternateIconName
        if currentIconName == "AppIconLight" {
            currentAppIcon = .light
        } else if currentIconName == "AppIconDark" {
            currentAppIcon = .dark
        } else {
            currentAppIcon = .automatic
        }
    }

    private func setAppIcon(_ option: AppIconOption) {
        let iconName = option.iconName
        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                print("Failed to change app icon: \(error.localizedDescription)")
            }
        }
    }
}
