//
//  Feed.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


// FILE: Models/Feed.swift
// PURPOSE: Core data model for a feed/source in VibeRSS
// SAFE TO EDIT: Yes, but keep properties consistent with persistence

import Foundation

struct Feed: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var url: URL
    var iconURL: URL?      // optional feed icon
    var folderID: UUID?    // optional folder assignment

    init(id: UUID = UUID(), title: String, url: URL, iconURL: URL? = nil, folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.iconURL = iconURL
        self.folderID = folderID
    }
}

// Terminology alias used throughout the app
typealias Source = Feed