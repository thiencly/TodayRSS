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

struct Folder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}