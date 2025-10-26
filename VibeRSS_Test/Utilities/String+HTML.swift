// FILE: Utilities/String+HTML.swift
// PURPOSE: Small helpers for trimming and stripping basic HTML
// SAFE TO EDIT: Yes, but be careful not to break regexes

import Foundation

extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func trimmedHTML() -> String {
        let s = self.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed()
    }
}
