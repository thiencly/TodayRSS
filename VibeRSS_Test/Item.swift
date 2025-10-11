//
//  Item.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/5/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
