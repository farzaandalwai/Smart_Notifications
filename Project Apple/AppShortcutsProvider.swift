//
//  AppShortcutsProvider.swift
//  Project Apple
//

import AppIntents

struct ProjectAppleShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogInstagramOpenIntent(),
            phrases: ["Open Instagram in \(.applicationName)"],
            shortTitle: "Open Instagram",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: LogInstagramCloseIntent(),
            phrases: ["Close Instagram in \(.applicationName)"],
            shortTitle: "Close Instagram",
            systemImageName: "arrow.down.forward.app"
        )
        AppShortcut(
            intent: LogWhatsAppOpenIntent(),
            phrases: ["Open WhatsApp in \(.applicationName)"],
            shortTitle: "Open WhatsApp",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: LogWhatsAppCloseIntent(),
            phrases: ["Close WhatsApp in \(.applicationName)"],
            shortTitle: "Close WhatsApp",
            systemImageName: "arrow.down.forward.app"
        )
        AppShortcut(
            intent: LogYouTubeOpenIntent(),
            phrases: ["Open YouTube in \(.applicationName)"],
            shortTitle: "Open YouTube",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: LogYouTubeCloseIntent(),
            phrases: ["Close YouTube in \(.applicationName)"],
            shortTitle: "Close YouTube",
            systemImageName: "arrow.down.forward.app"
        )
        AppShortcut(
            intent: LogChatGPTOpenIntent(),
            phrases: ["Open ChatGPT in \(.applicationName)"],
            shortTitle: "Open ChatGPT",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: LogChatGPTCloseIntent(),
            phrases: ["Close ChatGPT in \(.applicationName)"],
            shortTitle: "Close ChatGPT",
            systemImageName: "arrow.down.forward.app"
        )
        AppShortcut(
            intent: LogChessOpenIntent(),
            phrases: ["Open Chess in \(.applicationName)"],
            shortTitle: "Open Chess",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: LogChessCloseIntent(),
            phrases: ["Close Chess in \(.applicationName)"],
            shortTitle: "Close Chess",
            systemImageName: "arrow.down.forward.app"
        )
    }
}
