//
//  InterruptibilityPromptManager.swift
//  Project Apple
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class InterruptibilityPromptManager: ObservableObject {
    @Published var isAlertPresented = false

    private(set) var currentTrigger: String = "foreground"

    private let userDefaults = UserDefaults.standard
    private let calendar = Calendar.current

    private let dayStampKey = "interruptibility.dayStamp"
    private let dailyCountKey = "interruptibility.dailyCount"
    private let lastPromptAtKey = "interruptibility.lastPromptAtEpoch"
    private let notNowUntilKey = "interruptibility.notNowUntilEpoch"
    private let lastInteractionAtKey = "interruptibility.lastUserInteractionAtEpoch"

    func registerUserInteraction() {
        userDefaults.set(Date().timeIntervalSince1970, forKey: lastInteractionAtKey)
    }

    func maybeShowPrompt(
        trigger: String,
        scenePhase: ScenePhase,
        hasActiveModal: Bool
    ) {
        guard scenePhase == .active else { return }
        guard !hasActiveModal, !isAlertPresented else { return }
        guard isUserRecentlyInteracting else { return }

        resetDailyCountIfNeeded()

        let nowEpoch = Date().timeIntervalSince1970
        let dailyCount = userDefaults.integer(forKey: dailyCountKey)
        let lastPromptAt = userDefaults.double(forKey: lastPromptAtKey)
        let notNowUntil = userDefaults.double(forKey: notNowUntilKey)

        guard dailyCount < 3 else { return }
        guard (nowEpoch - lastPromptAt) >= (30 * 60) else { return }
        guard nowEpoch >= notNowUntil else { return }

        currentTrigger = trigger
        isAlertPresented = true
        userDefaults.set(nowEpoch, forKey: lastPromptAtKey)
        userDefaults.set(dailyCount + 1, forKey: dailyCountKey)
    }

    func handleNotNow() {
        let cooldownUntil = Date().addingTimeInterval(2 * 60 * 60).timeIntervalSince1970
        userDefaults.set(cooldownUntil, forKey: notNowUntilKey)
        isAlertPresented = false
    }

    func handleLabelSelection(
        label: String,
        context: ModelContext,
        modeRaw: String,
        notificationRequestIdentifier: String? = nil
    ) {
        var metadata: [String: Any] = [
            "label": label,
            "trigger": currentTrigger
        ]

        if let lastKnownApp = fetchLastKnownOpenedApp(context: context) {
            metadata["lastKnownApp"] = lastKnownApp
        }

        let metadataJson: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let json = String(data: data, encoding: .utf8) {
            metadataJson = json
        } else {
            metadataJson = "{}"
        }

        // Correction 4: explicit responses are separate events, marked with explicit confidence.
        let event = TelemetryEvent(
            eventId: UUID().uuidString,
            timestamp: Date(),
            mode: modeRaw,
            module: "esm",
            eventType: "interruptibility_label",
            sessionId: UUID().uuidString,
            metadataJson: metadataJson,
            outcomeConfidence: OutcomeConfidence.explicit.rawValue,
            notificationRequestIdentifier: notificationRequestIdentifier,
            pingId: notificationRequestIdentifier,
            explicitResponseOverride: label
        )

        context.insert(event)
        try? context.save()

        if let nrId = notificationRequestIdentifier {
            InterruptibilityPingScheduler.markPendingEntryExplicitResponseLogged(identifier: nrId)
        }

        isAlertPresented = false
    }

    // MARK: - Private

    private var isUserRecentlyInteracting: Bool {
        let lastInteractionEpoch = userDefaults.double(forKey: lastInteractionAtKey)
        guard lastInteractionEpoch > 0 else { return false }
        return (Date().timeIntervalSince1970 - lastInteractionEpoch) <= 20
    }

    private func resetDailyCountIfNeeded() {
        let today = dayStamp(for: Date())
        let storedDay = userDefaults.string(forKey: dayStampKey)
        if storedDay != today {
            userDefaults.set(today, forKey: dayStampKey)
            userDefaults.set(0, forKey: dailyCountKey)
        }
    }

    private func dayStamp(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let y = components.year ?? 0
        let m = components.month ?? 0
        let d = components.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func fetchLastKnownOpenedApp(context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<TelemetryEvent>(
            predicate: #Predicate { $0.eventType == "app_opened" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let latest = try? context.fetch(descriptor).first else {
            return nil
        }

        if let data = latest.metadataJson.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let sourceApp = json["sourceApp"],
           !sourceApp.isEmpty {
            return sourceApp
        }

        return latest.module.isEmpty ? nil : latest.module
    }
}
