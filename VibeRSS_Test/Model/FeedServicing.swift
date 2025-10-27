//
//  FeedServicing.swift
//  VibeRSS_Test
//
//  Created by You on Today.
//
// FILE: Protocols/FeedServicing.swift
// PURPOSE: Defines the contract for any service that can load feed items.
// SAFE TO EDIT: Yes, add methods as your domain grows.

import Foundation

// Abstraction for feed-loading behavior.
// Conformers (e.g., FeedService, MockFeedService) provide concrete implementations.
protocol FeedServicing {
    func loadItems(from url: URL) async throws -> [FeedItem]
}
