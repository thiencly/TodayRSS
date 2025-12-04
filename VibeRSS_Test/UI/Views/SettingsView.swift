import SwiftUI

struct SettingsView: View {
    @AppStorage("heroCollapsedOnLaunch") private var heroCollapsedOnLaunch: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Bindable private var syncManager = BackgroundSyncManager.shared

    var body: some View {
        NavigationStack {
            List {
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

                // MARK: - Hero Card Section
                Section {
                    Toggle("Collapse Hero Card on Launch", isOn: $heroCollapsedOnLaunch)
                } header: {
                    Text("Hero Card")
                } footer: {
                    Text("When enabled, the Today Highlights hero card will start collapsed when you open the app.")
                }
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
}
