//
//  LogAppOpenIntent.swift
//  Project Apple
//

import AppIntents
import Foundation

protocol TrackedAppOpenIntent: AppIntent {
    static var appName: String { get }
}

extension TrackedAppOpenIntent {
    func perform() async throws -> some IntentResult {
        let name = Self.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .result() }
        SharedEventBuffer.appendAppOpen(appName: name)
        return .result()
    }
}

protocol TrackedAppCloseIntent: AppIntent {
    static var appName: String { get }
}

extension TrackedAppCloseIntent {
    func perform() async throws -> some IntentResult {
        let name = Self.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .result() }
        SharedEventBuffer.appendAppClose(appName: name)
        return .result()
    }
}

// MARK: - Open intents (5 apps)

struct LogInstagramOpenIntent: TrackedAppOpenIntent {
    static var title: LocalizedStringResource = "Open — Instagram"
    static let appName = "Instagram"
}

struct LogWhatsAppOpenIntent: TrackedAppOpenIntent {
    static var title: LocalizedStringResource = "Open — WhatsApp"
    static let appName = "WhatsApp"
}

struct LogYouTubeOpenIntent: TrackedAppOpenIntent {
    static var title: LocalizedStringResource = "Open — YouTube"
    static let appName = "YouTube"
}

struct LogChatGPTOpenIntent: TrackedAppOpenIntent {
    static var title: LocalizedStringResource = "Open — ChatGPT"
    static let appName = "ChatGPT"
}

struct LogChessOpenIntent: TrackedAppOpenIntent {
    static var title: LocalizedStringResource = "Open — Chess"
    static let appName = "Chess"
}

// MARK: - Close intents (5 apps)

struct LogInstagramCloseIntent: TrackedAppCloseIntent {
    static var title: LocalizedStringResource = "Close — Instagram"
    static let appName = "Instagram"
}

struct LogWhatsAppCloseIntent: TrackedAppCloseIntent {
    static var title: LocalizedStringResource = "Close — WhatsApp"
    static let appName = "WhatsApp"
}

struct LogYouTubeCloseIntent: TrackedAppCloseIntent {
    static var title: LocalizedStringResource = "Close — YouTube"
    static let appName = "YouTube"
}

struct LogChatGPTCloseIntent: TrackedAppCloseIntent {
    static var title: LocalizedStringResource = "Close — ChatGPT"
    static let appName = "ChatGPT"
}

struct LogChessCloseIntent: TrackedAppCloseIntent {
    static var title: LocalizedStringResource = "Close — Chess"
    static let appName = "Chess"
}
