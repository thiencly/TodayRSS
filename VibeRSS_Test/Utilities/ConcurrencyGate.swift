
//
//  ConcurrencyGate.swift
//  TodayRSS
//
//  Purpose:
//  - A lightweight semaphore-like actor to cap concurrent tasks.
//  - Used to throttle feed loading and article prefetch work so UI remains responsive.
//
//  Used by:
//  - ContentView (global refresh: feedGate and articleGate)
//

import Foundation

actor ConcurrencyGate {
    private let limit: Int
    private var current: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func enter() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
        // Woken up by leave(); a slot is now ours
        current += 1
    }

    func leave() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            current = max(0, current - 1)
        }
    }

    func reset() {
        // Clear all waiters and release the counter so a new run starts fresh
        for cont in waiters {
            cont.resume()
        }
        waiters.removeAll()
        current = 0
    }

    // Convenience helper to avoid calling leave() from non-async contexts
    func withPermit<T>(operation: () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await operation()
    }
}
