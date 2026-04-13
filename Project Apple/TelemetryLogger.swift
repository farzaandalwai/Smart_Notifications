//
//  TelemetryLogger.swift
//  Project Apple
//

import Foundation
import SwiftData

// MARK: - Notification outcome domain types

enum NotificationOutcome: String {
    case opened
    case dismissed
    case ignored
}

enum OutcomeConfidence: String {
    case high
    case soft
    case explicit
}

// MARK: - Telemetry module

enum TelemetryModule: String {
    case home
    case notifications
    case live
    case voice
    case analytics
}

// MARK: - Logger

enum TelemetryLogger {
    /// Logs a telemetry event into SwiftData.
    /// All notification-outcome parameters default to nil so every existing call site continues to compile unchanged.
    static func log(
        context: ModelContext,
        mode: ExperimentMode,
        module: TelemetryModule,
        eventType: String,
        sessionId: String? = nil,
        metadata: [String: Any] = [:],
        notificationOutcome: NotificationOutcome? = nil,
        outcomeConfidence: OutcomeConfidence? = nil,
        actualDeliveryTimestampISO: String? = nil,
        notificationRequestIdentifier: String? = nil,
        pingId: String? = nil,
        explicitResponseOverride: String? = nil
    ) {
        let metadataJson: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let json = String(data: data, encoding: .utf8) {
            metadataJson = json
        } else {
            metadataJson = "{}"
        }

        let event = TelemetryEvent(
            eventId: UUID().uuidString,
            timestamp: Date(),
            mode: mode.rawValue,
            module: module.rawValue,
            eventType: eventType,
            sessionId: sessionId ?? UUID().uuidString,
            metadataJson: metadataJson,
            notificationOutcome: notificationOutcome?.rawValue,
            outcomeConfidence: outcomeConfidence?.rawValue,
            actualDeliveryTimestampISO: actualDeliveryTimestampISO,
            notificationRequestIdentifier: notificationRequestIdentifier,
            pingId: pingId,
            explicitResponseOverride: explicitResponseOverride
        )
        context.insert(event)
    }
}
