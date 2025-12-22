//
//  Folder.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


// FILE: Models/Folder.swift
// PURPOSE: Represents a folder that can contain multiple feeds
// SAFE TO EDIT: Yes, but keep fields consistent with persistence

import Foundation
import UIKit

// MARK: - Folder Icon Type

enum FolderIconType: Codable, Hashable {
    case automatic           // Uses SF Symbol based on folder name
    case sfSymbol(String)    // Custom SF Symbol name
    case emoji(String)       // Custom emoji

    // Coding keys for Codable
    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "automatic":
            self = .automatic
        case "sfSymbol":
            let value = try container.decode(String.self, forKey: .value)
            self = .sfSymbol(value)
        case "emoji":
            let value = try container.decode(String.self, forKey: .value)
            self = .emoji(value)
        default:
            self = .automatic
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .automatic:
            try container.encode("automatic", forKey: .type)
        case .sfSymbol(let name):
            try container.encode("sfSymbol", forKey: .type)
            try container.encode(name, forKey: .value)
        case .emoji(let emoji):
            try container.encode("emoji", forKey: .type)
            try container.encode(emoji, forKey: .value)
        }
    }
}

// MARK: - Folder Icon Mapper

struct FolderIconMapper {
    /// Maps folder name to best-fit SF Symbol
    static func suggestedIcon(for name: String) -> String {
        let lowercased = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Technology
        if matches(lowercased, ["tech", "technology", "software", "programming", "coding", "developer", "dev"]) {
            return "laptopcomputer"
        }
        if matches(lowercased, ["apple", "ios", "macos", "iphone", "ipad", "mac"]) {
            return "apple.logo"
        }
        if matches(lowercased, ["android", "google"]) {
            return "antenna.radiowaves.left.and.right"
        }
        if matches(lowercased, ["ai", "artificial intelligence", "machine learning", "ml"]) {
            return "brain.head.profile"
        }
        if matches(lowercased, ["robot", "automation"]) {
            return "gearshape.2"
        }
        if matches(lowercased, ["web", "internet", "online"]) {
            return "globe"
        }
        if matches(lowercased, ["cloud", "server", "hosting"]) {
            return "cloud"
        }
        if matches(lowercased, ["security", "privacy", "cyber"]) {
            return "lock.shield"
        }
        if matches(lowercased, ["code", "github", "git", "open source"]) {
            return "chevron.left.forwardslash.chevron.right"
        }

        // News & Media
        if matches(lowercased, ["news", "headlines", "breaking"]) {
            return "newspaper"
        }
        if matches(lowercased, ["politics", "government", "election"]) {
            return "building.columns"
        }
        if matches(lowercased, ["world", "international", "global"]) {
            return "globe.americas"
        }
        if matches(lowercased, ["local", "neighborhood", "community"]) {
            return "mappin.and.ellipse"
        }

        // Business & Finance
        if matches(lowercased, ["business", "corporate", "enterprise"]) {
            return "briefcase"
        }
        if matches(lowercased, ["finance", "money", "investing", "stocks", "market"]) {
            return "chart.line.uptrend.xyaxis"
        }
        if matches(lowercased, ["crypto", "bitcoin", "blockchain", "ethereum"]) {
            return "bitcoinsign.circle"
        }
        if matches(lowercased, ["startup", "entrepreneur", "venture"]) {
            return "lightbulb"
        }
        if matches(lowercased, ["economy", "economic"]) {
            return "banknote"
        }

        // Science & Education
        if matches(lowercased, ["science", "research", "study"]) {
            return "atom"
        }
        if matches(lowercased, ["space", "astronomy", "nasa", "rocket"]) {
            return "moon.stars"
        }
        if matches(lowercased, ["health", "medical", "medicine", "doctor"]) {
            return "heart.text.square"
        }
        if matches(lowercased, ["environment", "climate", "nature", "eco"]) {
            return "leaf"
        }
        if matches(lowercased, ["education", "learning", "school", "university"]) {
            return "book"
        }
        if matches(lowercased, ["math", "mathematics"]) {
            return "function"
        }
        if matches(lowercased, ["physics"]) {
            return "atom"
        }
        if matches(lowercased, ["chemistry", "chemical"]) {
            return "flask"
        }
        if matches(lowercased, ["biology", "life science"]) {
            return "leaf.arrow.triangle.circlepath"
        }

        // Entertainment
        if matches(lowercased, ["entertainment", "celebrity", "hollywood"]) {
            return "star"
        }
        if matches(lowercased, ["movies", "film", "cinema"]) {
            return "film"
        }
        if matches(lowercased, ["tv", "television", "shows", "streaming"]) {
            return "tv"
        }
        if matches(lowercased, ["music", "audio", "songs", "albums"]) {
            return "music.note"
        }
        if matches(lowercased, ["podcast", "podcasts"]) {
            return "mic"
        }
        if matches(lowercased, ["gaming", "games", "video games", "esports"]) {
            return "gamecontroller"
        }
        if matches(lowercased, ["anime", "manga", "japan"]) {
            return "sparkles"
        }
        if matches(lowercased, ["comics", "comic"]) {
            return "text.bubble"
        }

        // Sports
        if matches(lowercased, ["sports", "athletics"]) {
            return "sportscourt"
        }
        if matches(lowercased, ["football", "nfl"]) {
            return "football"
        }
        if matches(lowercased, ["basketball", "nba"]) {
            return "basketball"
        }
        if matches(lowercased, ["soccer", "football", "fifa"]) {
            return "soccerball"
        }
        if matches(lowercased, ["baseball", "mlb"]) {
            return "baseball"
        }
        if matches(lowercased, ["tennis"]) {
            return "tennis.racket"
        }
        if matches(lowercased, ["golf"]) {
            return "figure.golf"
        }
        if matches(lowercased, ["fitness", "workout", "exercise", "gym"]) {
            return "figure.run"
        }

        // Lifestyle
        if matches(lowercased, ["food", "cooking", "recipe", "culinary"]) {
            return "fork.knife"
        }
        if matches(lowercased, ["travel", "vacation", "tourism"]) {
            return "airplane"
        }
        if matches(lowercased, ["fashion", "style", "clothing"]) {
            return "tshirt"
        }
        if matches(lowercased, ["home", "house", "interior", "decor"]) {
            return "house"
        }
        if matches(lowercased, ["garden", "gardening", "plants"]) {
            return "leaf.circle"
        }
        if matches(lowercased, ["pets", "animals", "dog", "cat"]) {
            return "pawprint"
        }
        if matches(lowercased, ["parenting", "family", "kids", "children"]) {
            return "figure.2.and.child.holdinghands"
        }
        if matches(lowercased, ["relationship", "dating", "love"]) {
            return "heart"
        }

        // Design & Creative
        if matches(lowercased, ["design", "graphic", "ui", "ux"]) {
            return "paintpalette"
        }
        if matches(lowercased, ["art", "artwork", "artist"]) {
            return "paintbrush"
        }
        if matches(lowercased, ["photo", "photography"]) {
            return "camera"
        }
        if matches(lowercased, ["video", "youtube", "creator"]) {
            return "video"
        }
        if matches(lowercased, ["writing", "blog", "author"]) {
            return "pencil.line"
        }

        // Vehicles
        if matches(lowercased, ["cars", "auto", "automotive", "vehicles"]) {
            return "car"
        }
        if matches(lowercased, ["electric", "ev", "tesla"]) {
            return "bolt.car"
        }
        if matches(lowercased, ["motorcycle", "bike"]) {
            return "bicycle"
        }

        // Other
        if matches(lowercased, ["productivity", "work", "office"]) {
            return "checklist"
        }
        if matches(lowercased, ["social", "twitter", "facebook", "instagram"]) {
            return "bubble.left.and.bubble.right"
        }
        if matches(lowercased, ["deals", "shopping", "sale"]) {
            return "cart"
        }
        if matches(lowercased, ["humor", "funny", "comedy", "memes"]) {
            return "face.smiling"
        }
        if matches(lowercased, ["history", "historical"]) {
            return "clock.arrow.circlepath"
        }
        if matches(lowercased, ["religion", "spiritual", "faith"]) {
            return "hands.sparkles"
        }
        if matches(lowercased, ["weather", "forecast"]) {
            return "cloud.sun"
        }
        if matches(lowercased, ["personal", "diary", "journal"]) {
            return "book.closed"
        }
        if matches(lowercased, ["favorites", "favourite", "starred"]) {
            return "star.fill"
        }
        if matches(lowercased, ["read later", "reading list", "saved"]) {
            return "bookmark"
        }
        if matches(lowercased, ["misc", "miscellaneous", "other", "random"]) {
            return "tray"
        }

        // Default topic icon
        return "rectangle.stack"
    }

    /// Helper to check if name contains any of the keywords
    private static func matches(_ name: String, _ keywords: [String]) -> Bool {
        for keyword in keywords {
            if name.contains(keyword) {
                return true
            }
        }
        return false
    }
}

// MARK: - Folder Model

struct Folder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var iconType: FolderIconType

    init(id: UUID = UUID(), name: String, iconType: FolderIconType = .automatic) {
        self.id = id
        self.name = name
        self.iconType = iconType
    }

    // Migration: decode folders without iconType as automatic
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconType = try container.decodeIfPresent(FolderIconType.self, forKey: .iconType) ?? .automatic
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, iconType
    }

    /// Returns the display icon (SF Symbol name or emoji)
    var displayIcon: String {
        switch iconType {
        case .automatic:
            return FolderIconMapper.suggestedIcon(for: name)
        case .sfSymbol(let name):
            return name
        case .emoji(let emoji):
            return emoji
        }
    }

    /// Whether the icon is an emoji (vs SF Symbol)
    var isEmoji: Bool {
        if case .emoji = iconType {
            return true
        }
        return false
    }
}