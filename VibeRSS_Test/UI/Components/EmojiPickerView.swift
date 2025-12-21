//
//  EmojiPickerView.swift
//  VibeRSS_Test
//
//  Emoji picker for folder icon customization
//

import SwiftUI

struct EmojiPickerView: View {
    let folderName: String
    let currentIcon: FolderIconType
    let onSelect: (FolderIconType) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTint") private var appTint: String = AppTint.default.rawValue
    @State private var searchText: String = ""

    // Emoji categories with common emojis
    private let emojiCategories: [(name: String, icon: String, emojis: [String])] = [
        ("Smileys", "face.smiling", ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😋", "😛", "🤔", "🤨", "😐", "😑", "😶", "🙄", "😏", "😣", "😥", "😮", "🤐", "😯", "😪", "😫", "🥱", "😴", "🤤", "😌", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤥", "😬", "😔", "😷", "🤒", "🤕", "🤢", "🤮", "🤧", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "🥸", "😎", "🤓", "🧐"]),
        ("People", "person", ["👋", "🤚", "🖐", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🤟", "🤘", "🤙", "👈", "👉", "👆", "🖕", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "🤝", "🙏", "✍️", "💪", "🦾", "🦿", "🦵", "🦶", "👂", "🦻", "👃", "🧠", "🫀", "🫁", "🦷", "🦴", "👀", "👁", "👅", "👄", "👶", "🧒", "👦", "👧", "🧑", "👱", "👨", "🧔", "👩", "🧓", "👴", "👵"]),
        ("Animals", "hare", ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🪱", "🐛", "🦋", "🐌", "🐞", "🐜", "🪰", "🪲", "🪳", "🦟", "🦗", "🕷", "🦂", "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋", "🦈", "🐊"]),
        ("Food", "fork.knife", ["🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶", "🫑", "🌽", "🥕", "🫒", "🧄", "🧅", "🥔", "🍠", "🥐", "🥯", "🍞", "🥖", "🥨", "🧀", "🥚", "🍳", "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖", "🦴", "🌭", "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮", "🌯", "🫔", "🥗", "🥘", "🫕", "🥫", "🍝", "🍜", "🍲", "🍛"]),
        ("Activities", "sportscourt", ["⚽️", "🏀", "🏈", "⚾️", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑", "🥍", "🏏", "🪃", "🥅", "⛳️", "🪁", "🏹", "🎣", "🤿", "🥊", "🥋", "🎽", "🛹", "🛼", "🛷", "⛸", "🥌", "🎿", "⛷", "🏂", "🪂", "🏋️", "🤼", "🤸", "⛹️", "🤺", "🤾", "🏌️", "🏇", "⛸", "🏊", "🚣", "🧗", "🚴", "🚵", "🎖", "🏆", "🥇", "🥈", "🥉", "🏅", "🎪", "🤹", "🎭", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹"]),
        ("Travel", "airplane", ["🚗", "🚕", "🚙", "🚌", "🚎", "🏎", "🚓", "🚑", "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🦯", "🦽", "🦼", "🛴", "🚲", "🛵", "🏍", "🛺", "🚨", "🚔", "🚍", "🚘", "🚖", "🚡", "🚠", "🚟", "🚃", "🚋", "🚞", "🚝", "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "🚊", "🚉", "✈️", "🛫", "🛬", "🛩", "💺", "🛰", "🚀", "🛸", "🚁", "🛶", "⛵️", "🚤", "🛥", "🛳", "⛴", "🚢", "⚓️", "🪝", "⛽️", "🚧", "🚦", "🚥", "🚏", "🗺"]),
        ("Objects", "desktopcomputer", ["⌚️", "📱", "📲", "💻", "⌨️", "🖥", "🖨", "🖱", "🖲", "🕹", "🗜", "💽", "💾", "💿", "📀", "📼", "📷", "📸", "📹", "🎥", "📽", "🎞", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙", "🎚", "🎛", "🧭", "⏱", "⏲", "⏰", "🕰", "⌛️", "⏳", "📡", "🔋", "🔌", "💡", "🔦", "🕯", "🪔", "🧯", "🛢", "💸", "💵", "💴", "💶", "💷", "🪙", "💰", "💳", "💎", "⚖️", "🪜", "🧰", "🪛", "🔧", "🔨", "⚒", "🛠"]),
        ("Symbols", "heart", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "✝️", "☪️", "🕉", "☸️", "✡️", "🔯", "🕎", "☯️", "☦️", "🛐", "⛎", "♈️", "♉️", "♊️", "♋️", "♌️", "♍️", "♎️", "♏️", "♐️", "♑️", "♒️", "♓️", "🆔", "⚛️", "🉑", "☢️", "☣️", "📴", "📳", "🈶", "🈚️", "🈸", "🈺", "🈷️", "✴️", "🆚", "💮", "🉐", "㊙️", "㊗️", "🈴", "🈵", "🈹"]),
        ("Flags", "flag", ["🏳️", "🏴", "🏴‍☠️", "🏁", "🚩", "🎌", "🏳️‍🌈", "🏳️‍⚧️", "🇺🇸", "🇬🇧", "🇨🇦", "🇦🇺", "🇯🇵", "🇰🇷", "🇨🇳", "🇮🇳", "🇩🇪", "🇫🇷", "🇮🇹", "🇪🇸", "🇧🇷", "🇲🇽", "🇷🇺", "🇿🇦", "🇳🇿", "🇸🇬", "🇭🇰", "🇹🇼", "🇻🇳", "🇹🇭", "🇵🇭", "🇮🇩", "🇲🇾", "🇦🇪", "🇸🇦", "🇮🇱", "🇹🇷", "🇬🇷", "🇵🇹", "🇳🇱", "🇧🇪", "🇨🇭", "🇦🇹", "🇸🇪", "🇳🇴", "🇩🇰", "🇫🇮", "🇵🇱", "🇨🇿", "🇭🇺", "🇷🇴", "🇺🇦", "🇮🇪", "🇦🇷", "🇨🇴", "🇨🇱", "🇵🇪", "🇪🇬", "🇳🇬", "🇰🇪", "🇿🇼", "🇲🇦", "🇵🇰", "🇧🇩"])
    ]

    @State private var selectedCategory: Int = 0

    private var tintColor: Color {
        AppTint(rawValue: appTint)?.color ?? .blue
    }

    private var filteredEmojis: [String] {
        if searchText.isEmpty {
            return emojiCategories[selectedCategory].emojis
        }
        // Return all emojis when searching
        return emojiCategories.flatMap { $0.emojis }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Current icon preview
                currentIconPreview

                // Category tabs
                categoryTabs

                // Emoji grid
                emojiGrid
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var currentIconPreview: some View {
        VStack(spacing: 12) {
            // Preview of current selection
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                if case .emoji(let emoji) = currentIcon {
                    Text(emoji)
                        .font(.system(size: 40))
                } else {
                    let iconName = currentIcon == .automatic
                        ? FolderIconMapper.suggestedIcon(for: folderName)
                        : (currentIcon == .automatic ? "folder" : {
                            if case .sfSymbol(let name) = currentIcon { return name }
                            return "folder"
                        }())
                    Image(systemName: iconName)
                        .font(.system(size: 36))
                        .foregroundStyle(tintColor)
                }
            }

            Text(folderName)
                .font(.headline)
                .foregroundStyle(.primary)

            // Automatic icon button
            Button {
                onSelect(.automatic)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("Use Automatic Icon")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tintColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(tintColor.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(emojiCategories.enumerated()), id: \.offset) { index, category in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedCategory = index
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(selectedCategory == index ? tintColor : .secondary)
                                .frame(width: 36, height: 36)
                                .background(
                                    selectedCategory == index
                                        ? tintColor.opacity(0.15)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var emojiGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(filteredEmojis, id: \.self) { emoji in
                    Button {
                        onSelect(.emoji(emoji))
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
}
