//
//  ISO8601DateHelper.swift
//  Project Apple
//

import Foundation

enum ISO8601DateHelper {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func encodeISO(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func decodeISO(_ isoString: String) -> Date? {
        formatter.date(from: isoString)
    }
}
