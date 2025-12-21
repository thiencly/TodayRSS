//
//  FolderIndicatorView.swift
//  VibeRSS_Test
//
//  Horizontal folder indicator pills for news reel
//  Updated to match Apple's Liquid Glass segmented control pattern
//

import SwiftUI

/// Horizontal scrollable folder indicator with Apple's Liquid Glass segmented control style
struct FolderIndicatorView: View {
    let sources: [ReelSource]
    @Binding var selectedIndex: Int
    var onSelect: ((Int) -> Void)?

    @Namespace private var selectionAnimation
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            // Max width for the glass panel (leaves margin on edges)
            let maxPanelWidth = geometry.size.width - 32
            // Use content width if it fits, otherwise cap at max
            let panelWidth = min(contentWidth + 8, maxPanelWidth) // +8 for padding

            HStack {
                Spacer(minLength: 0)

                ScrollViewReader { proxy in
                    GlassEffectContainer {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                                    TopicPill(
                                        name: source.displayName,
                                        isSelected: index == selectedIndex,
                                        namespace: selectionAnimation
                                    ) {
                                        if let onSelect = onSelect {
                                            onSelect(index)
                                        } else {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                selectedIndex = index
                                            }
                                            HapticManager.shared.click()
                                        }
                                    }
                                    .id(index)
                                }
                            }
                            .background {
                                GeometryReader { contentGeometry in
                                    Color.clear
                                        .onAppear {
                                            contentWidth = contentGeometry.size.width
                                        }
                                        .onChange(of: sources.count) { _, _ in
                                            contentWidth = contentGeometry.size.width
                                        }
                                }
                            }
                        }
                        .scrollEdgeEffectStyle(.soft, for: .horizontal)
                        .onChange(of: selectedIndex) { _, newIndex in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                    .padding(4)
                    .clipShape(Capsule())
                    .mask {
                        HStack(spacing: 0) {
                            // Leading fade - stronger at edge
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.3),
                                    .init(color: .white, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 36)

                            // Middle - fully visible
                            Rectangle().fill(.white)

                            // Trailing fade - stronger at edge
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .clear, location: 0.7),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 36)
                        }
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .frame(width: contentWidth > 0 ? panelWidth : nil)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedIndex)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: contentWidth)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
        .frame(height: 60)
    }
}

/// Individual topic pill - text with sliding selection background
struct TopicPill: View {
    let name: String
    let isSelected: Bool
    var namespace: Namespace.ID
    var action: () -> Void

    @AppStorage("appTint") private var appTint: String = AppTint.default.rawValue

    private var tintColor: Color {
        (AppTint(rawValue: appTint) ?? .default).color
    }

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(.subheadline, design: .rounded, weight: isSelected ? .bold : .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        // Sliding selection indicator - the "thumb" in Apple's pattern
                        Capsule()
                            .fill(tintColor.opacity(0.9))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Compact version - dot indicators for limited space
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
