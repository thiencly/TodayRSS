
// FILE: Utilities/DateFormatter+RSS.swift
// PURPOSE: Shared date formatter for RSS-style dates
// SAFE TO EDIT: Yes, but keep format compatible with your feeds

import Foundation

extension DateFormatter {
    static let rfc822: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df
    }()
}
