//
//  FeedViewModel.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


//
//  FeedViewModel.swift
//  VibeRSS_Test
//
//  Created by You on Today.
//
// FILE: ViewModels/FeedViewModel.swift
// PURPOSE: Bridges Networking (FeedService) with Views by exposing items, loading, and error state.
// SAFE TO EDIT: Yes, view state and loading logic live here.

import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    // Published properties for the UI to react to
    @Published var items: [FeedItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // The service that fetches and parses feeds (protocol-based for testability and swapping implementations)
    private let service: FeedServicing

    // MARK: - Initialization
    // Dependency injection with a default implementation.
    // Pass a mock or alternate service in previews/tests.
    init(service: FeedServicing = FeedService()) {
        self.service = service
    }

    // Loads items from a given feed URL and updates published properties
    func load(feedURL: URL) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await service.loadItems(from: feedURL)
                self.items = fetched
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.items = []
            }
            self.isLoading = false
        }
    }

    // Optional: Clear items (e.g., pull-to-refresh reset or when switching feeds)
    func clear() {
        items = []
        errorMessage = nil
        isLoading = false
    }
}

