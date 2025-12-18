import SwiftUI
import UIKit

// MARK: - App Tint
enum AppTint: String, CaseIterable {
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case teal = "teal"
    case indigo = "indigo"

    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .indigo: return .indigo
        }
    }
}

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - App Icon Option
enum AppIconOption: String, CaseIterable {
    case auto = "auto"
    case light = "IconLight"
    case dark = "IconDark"
    case darkColor = "IconDarkColor"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        case .darkColor: return "Dark Color"
        }
    }

    var iconName: String? {
        switch self {
        case .auto: return nil // Will be determined by system appearance
        case .light: return "IconLight"
        case .dark: return "IconDark"
        case .darkColor: return "IconDarkColor"
        }
    }

    var previewImageName: String {
        switch self {
        case .auto, .light: return "IconLight"
        case .dark: return "IconDark"
        case .darkColor: return "IconDarkColor"
        }
    }

    static func iconForAppearance(_ isDark: Bool) -> String? {
        return isDark ? AppIconOption.darkColor.iconName : nil
    }
}

struct SettingsView: View {
    @AppStorage("heroCollapsedOnLaunch") private var heroCollapsedOnLaunch: Bool = false
    @AppStorage("showLatestView") private var showLatestView: Bool = true
    @AppStorage("showTodayView") private var showTodayView: Bool = true
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = AppIconOption.auto.rawValue
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.auto.rawValue
    @AppStorage("appTint") private var appTint: String = AppTint.blue.rawValue
    @AppStorage("readerFontSize") private var readerFontSize: Double = 18
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var syncManager = BackgroundSyncManager.shared
    @State private var showOnboarding = false
    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available

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

                // MARK: - Reader Section
                Section {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                if readerFontSize > 14 { readerFontSize -= 2 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Text("\(Int(readerFontSize))")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                                .frame(width: 30)

                            Button {
                                if readerFontSize < 28 { readerFontSize += 2 }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Reader")
                } footer: {
                    Text("Adjust the text size for the article reader view.")
                }

                // MARK: - Appearance Section
                Section {
                    Picker("Appearance", selection: Binding(
                        get: { AppearanceMode(rawValue: appearanceMode) ?? .auto },
                        set: { appearanceMode = $0.rawValue }
                    )) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose between light mode, dark mode, or auto to follow your device's setting.")
                }

                // MARK: - App Tint Section
                Section {
                    AppTintSelectionView(
                        selectedTint: Binding(
                            get: { AppTint(rawValue: appTint) ?? .blue },
                            set: { appTint = $0.rawValue }
                        )
                    )
                } header: {
                    Text("App Tint")
                } footer: {
                    Text("Choose the accent color used throughout the app.")
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
                    AppIconSelectionView(
                        selectedIcon: Binding(
                            get: { AppIconOption(rawValue: selectedAppIcon) ?? .auto },
                            set: { newValue in
                                selectedAppIcon = newValue.rawValue
                                updateAppIcon(to: newValue)
                            }
                        ),
                        colorScheme: colorScheme
                    )
                } header: {
                    Text("App Icon")
                } footer: {
                    Text("Auto changes the icon based on your device's light or dark mode setting.")
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
            }
            .onChange(of: colorScheme) { _, newScheme in
                // Update icon when system appearance changes (only if Auto is selected)
                if AppIconOption(rawValue: selectedAppIcon) == .auto {
                    let iconName = AppIconOption.iconForAppearance(newScheme == .dark)
                    setAppIcon(iconName)
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

    private func updateAppIcon(to option: AppIconOption) {
        if option == .auto {
            // Set icon based on current appearance
            let iconName = AppIconOption.iconForAppearance(colorScheme == .dark)
            setAppIcon(iconName)
        } else {
            setAppIcon(option.iconName)
        }
    }

    private func setAppIcon(_ iconName: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                print("Failed to set alternate icon: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - App Icon Selection View
struct AppIconSelectionView: View {
    @Binding var selectedIcon: AppIconOption
    let colorScheme: ColorScheme

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(AppIconOption.allCases, id: \.self) { option in
                AppIconCell(
                    option: option,
                    isSelected: selectedIcon == option,
                    colorScheme: colorScheme
                ) {
                    selectedIcon = option
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - App Icon Cell
struct AppIconCell: View {
    let option: AppIconOption
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var previewImage: UIImage? {
        if option == .auto {
            // For auto, show the icon that matches current appearance
            let imageName = colorScheme == .dark ? "IconDarkColor" : "IconLight"
            return loadPreviewImage(named: imageName)
        }
        return loadPreviewImage(named: option.previewImageName)
    }

    private func loadPreviewImage(named name: String) -> UIImage? {
        if let path = Bundle.main.path(forResource: name, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .foregroundStyle(.gray)
                            )
                    }

                    if option == .auto {
                        // Badge for Auto option
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 24, y: -24)
                    }
                }

                Text(option.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Tint Selection View
struct AppTintSelectionView: View {
    @Binding var selectedTint: AppTint

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(AppTint.allCases, id: \.self) { tint in
                AppTintCell(
                    tint: tint,
                    isSelected: selectedTint == tint
                ) {
                    selectedTint = tint
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - App Tint Cell
struct AppTintCell: View {
    let tint: AppTint
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(tint.color)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: tint.color.opacity(0.4), radius: 4, x: 0, y: 2)

                Text(tint.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tint.color)
                        .font(.caption)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
