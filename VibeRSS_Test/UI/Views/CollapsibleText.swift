import SwiftUI

struct CollapsibleText: View {
    let text: String
    let isExpanded: Bool
    private let collapsedLineCount: Int = 3

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(isExpanded ? nil : collapsedLineCount)
            .layoutPriority(1)
    }
}
