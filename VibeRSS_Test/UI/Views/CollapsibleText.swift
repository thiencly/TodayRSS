import SwiftUI

struct CollapsibleText: View {
    let text: String
    let isExpanded: Bool
    private let collapsedLineCount: Int = 3

    var body: some View {
        Group {
            if isExpanded {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                    .contentTransition(.opacity)
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(collapsedLineCount)
                    .layoutPriority(1)
                    .contentTransition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: isExpanded)
    }
}
