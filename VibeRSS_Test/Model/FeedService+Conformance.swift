//
//  FeedService+Conformance.swift
//  VibeRSS_Test
//
//  Created by You on Today.
//
// FILE: Services/FeedService+Conformance.swift
// PURPOSE: Declares conformance of FeedService to FeedServicing protocol.
// SAFE TO EDIT: Yes, remove or adjust if FeedService signature changes.

import Foundation

// Ensures the concrete service conforms to the protocol used by view models/tests.
extension FeedService: FeedServicing {}
