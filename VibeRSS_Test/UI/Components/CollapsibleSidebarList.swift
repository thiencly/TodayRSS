//
//  CollapsibleSidebarList.swift
//  VibeRSS_Test
//
//  Native iOS 26 style collapsible sidebar using UICollectionView
//  Provides Apple Notes-like expand/collapse animations with pure vertical sliding
//

import SwiftUI
import UIKit

// MARK: - Sidebar Item Model (Sendable for iOS 26 concurrency)

nonisolated enum SidebarItem: Hashable, @unchecked Sendable {
    // Section headers that expand/collapse
    case sectionsHeader(isExpanded: Bool)
    case sourcesHeader(isExpanded: Bool)

    // Fixed items at top
    case latest
    case today
    case saved(count: Int)

    // Content items - store only Sendable primitives
    case folder(id: UUID, name: String, feedCount: Int, hasNew: Bool)
    case folderFeed(id: UUID, title: String, iconURL: URL?, hasNew: Bool)
    case feed(id: UUID, title: String, iconURL: URL?, hasNew: Bool)

    var stableID: String {
        switch self {
        case .sectionsHeader: return "header-sections"
        case .sourcesHeader: return "header-sources"
        case .latest: return "fixed-latest"
        case .today: return "fixed-today"
        case .saved: return "fixed-saved"
        case .folder(let id, _, _, _): return "folder-\(id)"
        case .folderFeed(let id, _, _, _): return "folderFeed-\(id)"
        case .feed(let id, _, _, _): return "feed-\(id)"
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        lhs.stableID == rhs.stableID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableID)
    }
}

// MARK: - Navigation Destination (Sendable for iOS 26 concurrency)

enum SidebarDestination: Hashable, Sendable {
    case latest
    case today
    case saved
    case folder(id: UUID)
    case feed(id: UUID)
}

// MARK: - Sidebar Sections for hierarchical data

enum SidebarSection: Int, CaseIterable {
    case main = 0
}

// MARK: - UIKit Collection View Controller

final class SidebarCollectionVC: UIViewController {

    typealias DataSource = UICollectionViewDiffableDataSource<SidebarSection, SidebarItem>
    typealias Snapshot = NSDiffableDataSourceSnapshot<SidebarSection, SidebarItem>
    typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<SidebarItem>

    private var collectionView: UICollectionView!
    private var dataSource: DataSource!

    // Data
    var folders: [Folder] = []
    var feeds: [Feed] = []
    var showLatestView: Bool = true
    var showTodayView: Bool = true
    var savedCount: Int = 0

    // Expansion state
    var sectionsExpanded: Bool = true
    var sourcesExpanded: Bool = true

    // Content inset for glass card
    var topInset: CGFloat = 0
    private var hasSetInitialScrollPosition: Bool = false

    func updateContentInset(_ inset: CGFloat, animated: Bool = true) {
        guard let collectionView = collectionView else {
            topInset = inset
            return
        }

        let oldInset = topInset

        // Skip if inset hasn't changed significantly
        guard abs(inset - oldInset) > 0.5 else { return }

        topInset = inset

        // On initial setup, set without animation
        if !hasSetInitialScrollPosition {
            collectionView.contentInset.top = inset
            collectionView.verticalScrollIndicatorInsets.top = inset
            if inset > 0 {
                collectionView.setContentOffset(CGPoint(x: 0, y: -inset), animated: false)
                hasSetInitialScrollPosition = true
            }
        } else {
            // Check if content is currently at the top (showing first items)
            let isAtTop = collectionView.contentOffset.y <= -oldInset + 10

            if animated {
                // Card is expanding/collapsing - animate inset and scroll together
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
                    collectionView.contentInset.top = inset
                    collectionView.verticalScrollIndicatorInsets.top = inset
                    // If user was at top, keep them at top after inset change
                    if isAtTop {
                        collectionView.contentOffset = CGPoint(x: 0, y: -inset)
                    }
                }
            } else {
                collectionView.contentInset.top = inset
                collectionView.verticalScrollIndicatorInsets.top = inset
                if isAtTop {
                    collectionView.contentOffset = CGPoint(x: 0, y: -inset)
                }
            }
        }
    }

    // Callbacks
    var onNavigate: ((SidebarDestination) -> Void)?
    var onToggleSections: ((Bool) -> Void)?
    var onToggleSources: ((Bool) -> Void)?
    var onFolderContextMenu: ((Folder) -> UIMenu?)?
    var onFeedContextMenu: ((Feed) -> UIMenu?)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // Allow content to extend under navigation bar
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        setupCollectionView()
        setupDataSource()
        initializeSnapshot()
    }

    private func initializeSnapshot() {
        // Initialize the data source with the main section
        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setupCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .sidebar)
        config.showsSeparators = false
        config.headerMode = .none
        config.backgroundColor = .clear

        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self

        // Let system handle safe area, we add our card inset on top
        collectionView.contentInsetAdjustmentBehavior = .automatic

        // Don't clip - allow content to scroll under nav bar
        collectionView.clipsToBounds = false
        view.clipsToBounds = false

        // Set content inset and initial scroll position
        collectionView.contentInset.top = topInset
        collectionView.verticalScrollIndicatorInsets.top = topInset
        if topInset > 0 {
            collectionView.contentOffset = CGPoint(x: 0, y: -topInset)
            hasSetInitialScrollPosition = true
        }

        view.addSubview(collectionView)
    }

    private func setupDataSource() {
        // Header cell (Sections / Sources) - uses outlineDisclosure for native animation
        let headerReg = UICollectionView.CellRegistration<UICollectionViewListCell, SidebarItem> { [weak self] cell, indexPath, item in
            guard let self = self else { return }

            let (title, count): (String, Int) = {
                switch item {
                case .sectionsHeader: return ("Sections", self.folders.count)
                case .sourcesHeader: return ("Sources", self.feeds.count)
                default: return ("", 0)
                }
            }()

            var content = UIListContentConfiguration.sidebarHeader()
            content.text = title
            content.textProperties.font = .systemFont(ofSize: 22, weight: .bold).rounded()

            cell.contentConfiguration = content

            // Count label as custom accessory
            let countLabel = UILabel()
            countLabel.text = "\(count)"
            countLabel.font = .preferredFont(forTextStyle: .caption1)
            countLabel.textColor = .secondaryLabel

            // Use outlineDisclosure for native rotating chevron animation
            let disclosureOptions = UICellAccessory.OutlineDisclosureOptions(style: .header)

            cell.accessories = [
                .customView(configuration: .init(customView: countLabel, placement: .trailing())),
                .outlineDisclosure(options: disclosureOptions)
            ]

            cell.backgroundConfiguration = .clear()
        }

        // Fixed items (Latest, Today, Saved)
        let fixedReg = UICollectionView.CellRegistration<UICollectionViewListCell, SidebarItem> { cell, indexPath, item in
            var content = UIListContentConfiguration.sidebarCell()

            switch item {
            case .latest:
                content.text = "Latest"
                content.image = UIImage(systemName: "clock")
            case .today:
                content.text = "Today"
                content.image = UIImage(systemName: "newspaper")
            case .saved(let count):
                content.text = "Saved"
                content.image = UIImage(systemName: "heart.fill")
                content.imageProperties.tintColor = .systemRed

                if count > 0 {
                    let countLabel = UILabel()
                    countLabel.text = "\(count)"
                    countLabel.font = .preferredFont(forTextStyle: .caption1)
                    countLabel.textColor = .secondaryLabel
                    cell.accessories = [
                        .customView(configuration: .init(customView: countLabel, placement: .trailing()))
                    ]
                } else {
                    cell.accessories = []
                }
            default: break
            }

            cell.contentConfiguration = content
            cell.backgroundConfiguration = .listSidebarCell()
        }

        // Folder cell
        let folderReg = UICollectionView.CellRegistration<UICollectionViewListCell, SidebarItem> { cell, indexPath, item in
            guard case .folder(_, let name, let count, let hasNew) = item else { return }

            var content = UIListContentConfiguration.sidebarCell()
            content.text = name
            content.image = UIImage(systemName: "folder")

            cell.contentConfiguration = content

            var accessories: [UICellAccessory] = []

            if hasNew {
                let dot = UIView()
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = 4
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 8),
                    dot.heightAnchor.constraint(equalToConstant: 8)
                ])
                accessories.append(.customView(configuration: .init(customView: dot, placement: .trailing())))
            }

            let countLabel = UILabel()
            countLabel.text = "\(count)"
            countLabel.font = .preferredFont(forTextStyle: .caption1)
            countLabel.textColor = .secondaryLabel
            accessories.append(.customView(configuration: .init(customView: countLabel, placement: .trailing())))

            cell.accessories = accessories
            cell.backgroundConfiguration = .listSidebarCell()
        }

        // Folder feed cell (indented)
        let folderFeedReg = UICollectionView.CellRegistration<UICollectionViewListCell, SidebarItem> { cell, indexPath, item in
            guard case .folderFeed(_, let title, let iconURL, let hasNew) = item else { return }

            var content = UIListContentConfiguration.sidebarCell()
            content.text = title
            content.image = UIImage(systemName: "doc.text")
            content.imageProperties.maximumSize = CGSize(width: 24, height: 24)

            // Load icon async
            if let iconURL = iconURL {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: iconURL),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            content.image = img
                            content.imageProperties.cornerRadius = 4
                            cell.contentConfiguration = content
                        }
                    }
                }
            }

            cell.contentConfiguration = content
            cell.indentationLevel = 1
            cell.indentationWidth = 20

            if hasNew {
                let dot = UIView()
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = 4
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 8),
                    dot.heightAnchor.constraint(equalToConstant: 8)
                ])
                cell.accessories = [.customView(configuration: .init(customView: dot, placement: .trailing()))]
            } else {
                cell.accessories = []
            }

            cell.backgroundConfiguration = .listSidebarCell()
        }

        // Feed cell
        let feedReg = UICollectionView.CellRegistration<UICollectionViewListCell, SidebarItem> { cell, indexPath, item in
            guard case .feed(_, let title, let iconURL, let hasNew) = item else { return }

            var content = UIListContentConfiguration.sidebarCell()
            content.text = title
            content.image = UIImage(systemName: "doc.text")
            content.imageProperties.maximumSize = CGSize(width: 24, height: 24)

            // Load icon async
            if let iconURL = iconURL {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: iconURL),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            content.image = img
                            content.imageProperties.cornerRadius = 4
                            cell.contentConfiguration = content
                        }
                    }
                }
            }

            cell.contentConfiguration = content

            if hasNew {
                let dot = UIView()
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = 4
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 8),
                    dot.heightAnchor.constraint(equalToConstant: 8)
                ])
                cell.accessories = [.customView(configuration: .init(customView: dot, placement: .trailing()))]
            } else {
                cell.accessories = []
            }

            cell.backgroundConfiguration = .listSidebarCell()
        }

        dataSource = DataSource(collectionView: collectionView) { (cv: UICollectionView, indexPath: IndexPath, item: SidebarItem) -> UICollectionViewCell? in
            switch item {
            case .sectionsHeader, .sourcesHeader:
                return cv.dequeueConfiguredReusableCell(using: headerReg, for: indexPath, item: item)
            case .latest, .today, .saved:
                return cv.dequeueConfiguredReusableCell(using: fixedReg, for: indexPath, item: item)
            case .folder:
                return cv.dequeueConfiguredReusableCell(using: folderReg, for: indexPath, item: item)
            case .folderFeed:
                return cv.dequeueConfiguredReusableCell(using: folderFeedReg, for: indexPath, item: item)
            case .feed:
                return cv.dequeueConfiguredReusableCell(using: feedReg, for: indexPath, item: item)
            }
        }

        // Handle expand/collapse events from outline disclosure
        dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] item in
            guard let self = self else { return }
            switch item {
            case .sectionsHeader:
                self.sectionsExpanded = true
                self.onToggleSections?(true)
            case .sourcesHeader:
                self.sourcesExpanded = true
                self.onToggleSources?(true)
            default:
                break
            }
        }

        dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] item in
            guard let self = self else { return }
            switch item {
            case .sectionsHeader:
                self.sectionsExpanded = false
                self.onToggleSections?(false)
            case .sourcesHeader:
                self.sourcesExpanded = false
                self.onToggleSources?(false)
            default:
                break
            }
        }
    }

    func applyData(animated: Bool = true) {
        // Use section snapshot for hierarchical data with native expand/collapse animations
        var sectionSnapshot = SectionSnapshot()

        // === SECTIONS HEADER with children ===
        let sectionsHeader = SidebarItem.sectionsHeader(isExpanded: sectionsExpanded)
        sectionSnapshot.append([sectionsHeader])

        // Children of Sections header
        var sectionsChildren: [SidebarItem] = []

        if showLatestView {
            sectionsChildren.append(.latest)
        }
        if showTodayView {
            sectionsChildren.append(.today)
        }
        sectionsChildren.append(.saved(count: savedCount))

        // Folders and their feeds
        for folder in folders {
            let folderFeeds = feeds.filter { $0.folderID == folder.id }
            let hasNew = folderFeeds.contains { ArticleReadStateManager.sourceHasNewArticlesSync($0.id) }
            sectionsChildren.append(.folder(id: folder.id, name: folder.name, feedCount: folderFeeds.count, hasNew: hasNew))

            // Folder's feeds (indented)
            for feed in folderFeeds {
                let feedHasNew = ArticleReadStateManager.sourceHasNewArticlesSync(feed.id)
                sectionsChildren.append(.folderFeed(id: feed.id, title: feed.title, iconURL: feed.iconURL, hasNew: feedHasNew))
            }
        }

        sectionSnapshot.append(sectionsChildren, to: sectionsHeader)

        // Expand or collapse based on state
        if sectionsExpanded {
            sectionSnapshot.expand([sectionsHeader])
        } else {
            sectionSnapshot.collapse([sectionsHeader])
        }

        // === SOURCES HEADER with children ===
        let sourcesHeader = SidebarItem.sourcesHeader(isExpanded: sourcesExpanded)
        sectionSnapshot.append([sourcesHeader])

        // Children of Sources header
        var sourcesChildren: [SidebarItem] = []
        for feed in feeds {
            let hasNew = ArticleReadStateManager.sourceHasNewArticlesSync(feed.id)
            sourcesChildren.append(.feed(id: feed.id, title: feed.title, iconURL: feed.iconURL, hasNew: hasNew))
        }

        sectionSnapshot.append(sourcesChildren, to: sourcesHeader)

        // Expand or collapse based on state
        if sourcesExpanded {
            sectionSnapshot.expand([sourcesHeader])
        } else {
            sectionSnapshot.collapse([sourcesHeader])
        }

        // Apply the section snapshot to the main section
        dataSource.apply(sectionSnapshot, to: .main, animatingDifferences: animated)
    }

    // Toggle expansion with native sliding animation
    private func toggleSectionsExpansion() {
        // Get current snapshot
        var snapshot = dataSource.snapshot(for: .main)

        // Find the sections header (use any isExpanded value since stableID matches)
        let sectionsHeader = SidebarItem.sectionsHeader(isExpanded: sectionsExpanded)

        // Check current state and toggle
        let isCurrentlyExpanded = snapshot.isExpanded(sectionsHeader)
        if isCurrentlyExpanded {
            snapshot.collapse([sectionsHeader])
        } else {
            snapshot.expand([sectionsHeader])
        }

        // Update our state to match
        sectionsExpanded = !isCurrentlyExpanded
        onToggleSections?(sectionsExpanded)

        // Apply with animation for sliding effect
        dataSource.apply(snapshot, to: .main, animatingDifferences: true)
    }

    private func toggleSourcesExpansion() {
        // Get current snapshot
        var snapshot = dataSource.snapshot(for: .main)

        // Find the sources header (use any isExpanded value since stableID matches)
        let sourcesHeader = SidebarItem.sourcesHeader(isExpanded: sourcesExpanded)

        // Check current state and toggle
        let isCurrentlyExpanded = snapshot.isExpanded(sourcesHeader)
        if isCurrentlyExpanded {
            snapshot.collapse([sourcesHeader])
        } else {
            snapshot.expand([sourcesHeader])
        }

        // Update our state to match
        sourcesExpanded = !isCurrentlyExpanded
        onToggleSources?(sourcesExpanded)

        // Apply with animation for sliding effect
        dataSource.apply(snapshot, to: .main, animatingDifferences: true)
    }
}

// MARK: - Collection View Delegate

extension SidebarCollectionVC: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .sectionsHeader:
            // Toggle via snapshot for sliding animation (outline disclosure also handles this)
            toggleSectionsExpansion()

        case .sourcesHeader:
            // Toggle via snapshot for sliding animation (outline disclosure also handles this)
            toggleSourcesExpansion()

        case .latest:
            onNavigate?(.latest)

        case .today:
            onNavigate?(.today)

        case .saved:
            onNavigate?(.saved)

        case .folder(let id, _, _, _):
            onNavigate?(.folder(id: id))

        case .folderFeed(let id, _, _, _):
            onNavigate?(.feed(id: id))

        case .feed(let id, _, _, _):
            onNavigate?(.feed(id: id))
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }

        switch item {
        case .folder(let id, _, _, _):
            guard let folder = folders.first(where: { $0.id == id }) else { return nil }
            guard let menu = onFolderContextMenu?(folder) else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }

        case .feed(let id, _, _, _), .folderFeed(let id, _, _, _):
            guard let feed = feeds.first(where: { $0.id == id }) else { return nil }
            guard let menu = onFeedContextMenu?(feed) else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }

        default:
            return nil
        }
    }
}

// MARK: - SwiftUI Wrapper

struct CollapsibleSidebarList: UIViewControllerRepresentable {
    let folders: [Folder]
    let feeds: [Feed]
    let showLatestView: Bool
    let showTodayView: Bool
    let savedCount: Int
    @Binding var sectionsExpanded: Bool
    @Binding var sourcesExpanded: Bool
    var topInset: CGFloat = 0
    var onNavigate: ((SidebarDestination) -> Void)?
    var onFolderContextMenu: ((Folder) -> UIMenu?)?
    var onFeedContextMenu: ((Feed) -> UIMenu?)?

    func makeUIViewController(context: Context) -> SidebarCollectionVC {
        let vc = SidebarCollectionVC()
        configureVC(vc)
        // Set initial content inset (may be 0 if hero card not measured yet)
        vc.updateContentInset(topInset)
        return vc
    }

    func updateUIViewController(_ vc: SidebarCollectionVC, context: Context) {
        configureVC(vc)

        // Update content inset for glass card overlay AFTER configuring data
        // This must happen after configureVC to properly track old vs new inset
        vc.updateContentInset(topInset)

        // Always apply data to keep list in sync
        vc.applyData(animated: false)
    }

    private func configureVC(_ vc: SidebarCollectionVC) {
        vc.folders = folders
        vc.feeds = feeds
        vc.showLatestView = showLatestView
        vc.showTodayView = showTodayView
        vc.savedCount = savedCount
        vc.sectionsExpanded = sectionsExpanded
        vc.sourcesExpanded = sourcesExpanded
        // Note: Do NOT set vc.topInset here - let updateContentInset manage it
        // Setting it here would break the old vs new comparison in updateContentInset

        vc.onNavigate = onNavigate

        vc.onToggleSections = { expanded in
            sectionsExpanded = expanded
        }

        vc.onToggleSources = { expanded in
            sourcesExpanded = expanded
        }

        vc.onFolderContextMenu = onFolderContextMenu
        vc.onFeedContextMenu = onFeedContextMenu
    }
}

// MARK: - Font Extension

fileprivate extension UIFont {
    func rounded() -> UIFont {
        guard let desc = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: desc, size: pointSize)
    }
}
