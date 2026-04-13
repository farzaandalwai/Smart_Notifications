//
//  TelemetryEvent.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import Foundation
import SwiftData

@Model
class TelemetryEvent {
    @Attribute(.unique) var eventId: String
    var id: UUID
    var timestamp: Date
    var mode: String
    var module: String
    var eventType: String
    var sessionId: String
    var metadataJson: String
    // Notification outcome enrichment — nil for all legacy events; SwiftData defaults missing columns to nil.
    var notificationOutcome: String?
    var outcomeConfidence: String?
    var actualDeliveryTimestampISO: String?
    var notificationRequestIdentifier: String?
    var pingId: String?
    var explicitResponseOverride: String?

    init(
        eventId: String,
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: String,
        module: String,
        eventType: String,
        sessionId: String,
        metadataJson: String,
        notificationOutcome: String? = nil,
        outcomeConfidence: String? = nil,
        actualDeliveryTimestampISO: String? = nil,
        notificationRequestIdentifier: String? = nil,
        pingId: String? = nil,
        explicitResponseOverride: String? = nil
    ) {
        self.eventId = eventId
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.module = module
        self.eventType = eventType
        self.sessionId = sessionId
        self.metadataJson = metadataJson
        self.notificationOutcome = notificationOutcome
        self.outcomeConfidence = outcomeConfidence
        self.actualDeliveryTimestampISO = actualDeliveryTimestampISO
        self.notificationRequestIdentifier = notificationRequestIdentifier
        self.pingId = pingId
        self.explicitResponseOverride = explicitResponseOverride
    }
}
