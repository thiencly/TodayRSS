//
//  DayAnchor.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


//
//  DayAnchors.swift
//  TodayRSS
//
//  Purpose:
//  - Provides lightweight utilities to compute and display the current day anchor
//    while scrolling article lists.
//  - Includes a preference key (`DayAnchorsKey`), a geometry reporter (`DayAnchorReporter`),
//    and a compact UI chip (`FloatingDayChip`) used by list screens.
//
//  Used by:
//  - FeedDetailView
//  - FolderDetailView
//  - AllArticlesView
//

import SwiftUI

// MARK: - Floating Day Indicator support (extracted)

public struct DayAnchor: Equatable {
    public let dayStart: Date
    public let minY: CGFloat
}

public struct DayAnchorsKey: PreferenceKey {
    public static var defaultValue: [DayAnchor] = []
    public static func reduce(value: inout [DayAnchor], nextValue: () -> [DayAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

// Reports the vertical position of a row’s day group to the parent List/ScrollView.
public struct DayAnchorReporter: View {
    public let date: Date?
    public let coordinateSpaceName: String

    public init(date: Date?, coordinateSpaceName: String) {
        self.date = date
        self.coordinateSpaceName = coordinateSpaceName
    }

    public var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: DayAnchorsKey.self, value: {
                    guard let date else { return [] }
                    let dayStart = Calendar.current.startOfDay(for: date)
                    let minY = proxy.frame(in: .named(coordinateSpaceName)).minY
                    return [DayAnchor(dayStart: dayStart, minY: minY)]
                }())
        }
    }
}

// Compact "Today / Yesterday / <date>" chip shown pinned at the top.
public struct FloatingDayChip: View {
    public let date: Date

    // Cached DateFormatter for performance (creating DateFormatter is expensive)
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        Text(dayLabel(for: date))
            .font(.callout.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.secondary.opacity(0.2))
            )
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return Self.dateFormatter.string(from: date)
    }
}