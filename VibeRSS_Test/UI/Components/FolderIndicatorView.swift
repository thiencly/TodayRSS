//
//  FolderIndicatorView.swift
//  VibeRSS_Test
//
//  Horizontal folder indicator pills for news reel
//

import SwiftUI

/// Horizontal scrollable folder indicator with pills
struct FolderIndicatorView: View {
    let sources: [ReelSource]
    @Binding var selectedIndex: Int
    var onSelect: ((Int) -> Void)?

    @Namespace private var pillAnimation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        FolderPill(
                            name: source.displayName,
                            isSelected: index == selectedIndex,
                            namespace: pillAnimation
                        )
                        .id(index)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedIndex = index
                            }
                            onSelect?(index)
                            HapticManager.shared.click()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

/// Individual folder pill with Liquid Glass UI
struct FolderPill: View {
    let name: String
    let isSelected: Bool
    var namespace: Namespace.ID

    var body: some View {
        Text(name)
            .font(.subheadline)
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(isSelected ? .regular.interactive() : .regular)
            .contentShape(Capsule())
    }
}

/// Compact version for when space is limited
struct CompactFolderIndicatorView: View {
    let sources: [ReelSource]
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.4))
                    .frame(width: index == selectedIndex ? 8 : 6, height: index == selectedIndex ? 8 : 6)
                    .animation(.spring(response: 0.25), value: selectedIndex)
            }
        }
    }
}
