//
//  NotificationCenterDelegate.swift
//  Project Apple
//

import Foundation
import SwiftData
import UserNotifications

final class AppNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationCenterDelegate()

    private var modelContainer: ModelContainer?
    /// In-memory fast-path cache; UserDefaults is the durable source of truth (Correction 3).
    private var loggedOutcomeKeys: Set<String> = []
    private let outcomeLock = NSLock()
    private let appGroupId = "group.com.farzaan.projectapple"

    /// Set when the user body-taps a ping notification (default action).
    /// RootTabView watches this and shows the in-app Yes/No/Not-now alert.
    var pendingPingId: String?

    private override init() { super.init() }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        UNUserNotificationCenter.current().delegate = self
        InterruptibilityPingScheduler.registerCategory()
    }

    // MARK: - Legacy ping-sent method (kept for backward compatibility; no longer called by the scheduler)

    func logPingSent(notificationId: String, modeRaw: String, scheduledForISO: String) {
        guard let modelContainer = modelContainer else { return }
        let metadata: [String: Any] = [
            "notificationId":  notificationId,
            "scheduledForISO": scheduledForISO
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata),
              let metadataJson = String(data: data, encoding: .utf8) else { return }

        DispatchQueue.main.async {
            let context = modelContainer.mainContext
            let event = TelemetryEvent(
                eventId:      "ping_sent_\(notificationId)",
                timestamp:    Date(),
                mode:         modeRaw,
                module:       "notifications",
                eventType:    "ping_sent",
                sessionId:    UUID().uuidString,
                metadataJson: metadataJson
            )
            context.insert(event)
            try? context.save()
        }
    }

    /// Kept for non-ping notification lifecycle events.
    func logScheduledNotification(
        notificationId: String,
        modeRaw: String,
        kind: String,
        isTest: Bool,
        metadata: [String: Any] = [:]
    ) {
        let payload = NotificationPayload(notificationId: notificationId, kind: kind, isTest: isTest)
        logOutcome(eventType: "notif_scheduled", payload: payload, modeRawOverride: modeRaw, extraMetadata: metadata)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let categoryId = notification.request.content.categoryIdentifier

        if categoryId == InterruptibilityPingScheduler.categoryId {
            // Correction 1: do NOT log a TelemetryEvent here.
            // Store the actual OS-recorded delivery time so didReceive can use it in the outcome event.
            let deliveryISO = ISO8601DateHelper.encodeISO(notification.date)
            InterruptibilityPingScheduler.updatePendingEntryDelivery(
                identifier: notification.request.identifier,
                deliveryISO: deliveryISO
            )
        } else {
            logOutcome(eventType: "notif_presented", payload: notificationPayload(from: notification))
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId          = response.actionIdentifier
        let categoryId        = response.notification.request.content.categoryIdentifier
        let payload           = notificationPayload(from: response.notification)
        let notificationId    = payload.notificationId
        let requestIdentifier = response.notification.request.identifier

        // Guard against identifier drift: request.identifier and userInfo["notificationId"]
        // must always be equal for ping notifications. If they ever diverge (e.g. because
        // schedulePing is edited to use different values), the pending-store lookup in the
        // in-app prompt path would silently miss. This assertion catches that at development time.
        #if DEBUG
        if let userInfoId = response.notification.request.content.userInfo["notificationId"] as? String {
            assert(
                requestIdentifier == userInfoId,
                "[PingDebug] identifier drift: request.identifier='\(requestIdentifier)' userInfo[\"notificationId\"]='\(userInfoId)'"
            )
        }
        #endif

        if categoryId == InterruptibilityPingScheduler.categoryId {
            let deviceSnapshot = DeviceContextCollector.snapshot(appGroupId: SharedEventBuffer.appGroupId)
            let deviceMetadata: [String: String] = [
                "device_batteryBucket": deviceSnapshot["batteryBucket"] ?? "unknown",
                "device_isCharging":    deviceSnapshot["isCharging"]    ?? "unknown",
                "device_lowPowerMode":  deviceSnapshot["lowPowerMode"]  ?? "0",
                "device_audioPlaying":  deviceSnapshot["audioPlaying"]  ?? "0",
                "device_networkType":   deviceSnapshot["networkType"]   ?? "unknown"
            ]

            // Resolve delivery timestamp.
            // Priority: (1) stored by willPresent for foreground delivery,
            //           (2) notification.date recorded by the OS for background delivery.
            let pendingEntry = InterruptibilityPingScheduler.loadPendingEntry(identifier: requestIdentifier)
            let deliveryISO  = pendingEntry?.actualDeliveryISO
                ?? ISO8601DateHelper.encodeISO(response.notification.date)
            let modeRaw      = pendingEntry?.modeRaw
                ?? UserDefaults(suiteName: appGroupId)?.string(forKey: "experimentMode")
                ?? UserDefaults.standard.string(forKey: "experimentMode")
                ?? ExperimentMode.baseline.rawValue

            // Passive notification_outcome — logged only for the two cases where the outcome
            // is unambiguously observable from the OS:
            //   • body tap  → opened  (UNNotificationDefaultActionIdentifier)
            //   • swipe dismiss → dismissed  (UNNotificationDismissActionIdentifier)
            // Custom action buttons (Yes / No / Not Now) produce a complete explicit
            // interruptibility_response event; no passive outcome is added for them.
            if actionId == UNNotificationDefaultActionIdentifier {
                logNotificationOutcome(
                    identifier:  requestIdentifier,
                    pingId:      notificationId,
                    outcome:     .opened,
                    confidence:  .high,
                    deliveryISO: deliveryISO,
                    modeRaw:     modeRaw
                )
                InterruptibilityPingScheduler.markPendingEntryOutcomeLogged(
                    identifier: requestIdentifier,
                    outcome:    NotificationOutcome.opened.rawValue
                )
            } else if actionId == UNNotificationDismissActionIdentifier {
                logNotificationOutcome(
                    identifier:  requestIdentifier,
                    pingId:      notificationId,
                    outcome:     .dismissed,
                    confidence:  .high,
                    deliveryISO: deliveryISO,
                    modeRaw:     modeRaw
                )
                InterruptibilityPingScheduler.markPendingEntryOutcomeLogged(
                    identifier: requestIdentifier,
                    outcome:    NotificationOutcome.dismissed.rawValue
                )
            }

            // Explicit responses — separate TelemetryEvents via SharedEventBuffer (unchanged flow).
            // markPendingEntryExplicitResponseLogged is called after each so ignored reconciliation skips this ping.
            if actionId == InterruptibilityPingScheduler.actionYes {
                SharedEventBuffer.appendInterruptibilityResponse(
                    label: "yes", notificationId: notificationId,
                    responseSource: "action_button", additionalMetadata: deviceMetadata
                )
                InterruptibilityPingScheduler.markPendingEntryExplicitResponseLogged(identifier: requestIdentifier)
                print("[PingDebug] response yes via action_button notificationId=\(notificationId)")

            } else if actionId == InterruptibilityPingScheduler.actionNo {
                SharedEventBuffer.appendInterruptibilityResponse(
                    label: "no", notificationId: notificationId,
                    responseSource: "action_button", additionalMetadata: deviceMetadata
                )
                InterruptibilityPingScheduler.markPendingEntryExplicitResponseLogged(identifier: requestIdentifier)
                print("[PingDebug] response no via action_button notificationId=\(notificationId)")

            } else if actionId == InterruptibilityPingScheduler.actionNotNow {
                SharedEventBuffer.appendInterruptibilityResponse(
                    label: "not_now", notificationId: notificationId,
                    responseSource: "action_button", additionalMetadata: deviceMetadata
                )
                InterruptibilityPingScheduler.markPendingEntryExplicitResponseLogged(identifier: requestIdentifier)
                SharedEventBuffer.setInterruptibilityNotNowCooldown(hours: 2)
                InterruptibilityPingScheduler.applyNotNowCooldown(hours: 2)
                print("[PingDebug] response not_now via action_button notificationId=\(notificationId)")

            } else if actionId == UNNotificationDefaultActionIdentifier {
                // Body tap — RootTabView will present the in-app Yes/No/Not-now prompt.
                pendingPingId = notificationId
                print("[PingDebug] body tap, pendingPingId=\(notificationId)")
            }

        } else {
            // Non-ping notifications: keep existing lifecycle logging unchanged.
            if actionId == UNNotificationDismissActionIdentifier {
                logOutcome(eventType: "notif_dismissed", payload: payload, actionId: actionId)
            } else {
                logOutcome(eventType: "notif_opened", payload: payload, actionId: actionId)
            }
        }
        completionHandler()
    }

    // MARK: - Ping outcome logging

    /// Logs exactly one `notification_outcome` TelemetryEvent per (kind, identifier) pair.
    /// Dedup is checked and written to both the in-memory cache (fast path) and UserDefaults
    /// (persisted across relaunches) per Correction 3.
    private func logNotificationOutcome(
        identifier:  String,
        pingId:      String,
        outcome:     NotificationOutcome,
        confidence:  OutcomeConfidence,
        deliveryISO: String?,
        modeRaw:     String
    ) {
        let kind = outcome.rawValue
        guard !isOutcomeAlreadyLogged(kind: kind, identifier: identifier) else { return }
        guard let modelContainer = modelContainer else { return }
        markOutcomeLogged(kind: kind, identifier: identifier)

        DispatchQueue.main.async {
            let context = modelContainer.mainContext
            let event = TelemetryEvent(
                eventId:                    "outcome_\(kind)_\(identifier)",
                timestamp:                  Date(),
                mode:                       modeRaw,
                module:                     "notifications",
                eventType:                  "notification_outcome",
                sessionId:                  UUID().uuidString,
                metadataJson:               "{}",
                notificationOutcome:        kind,
                outcomeConfidence:          confidence.rawValue,
                actualDeliveryTimestampISO: deliveryISO,
                notificationRequestIdentifier: identifier,
                pingId:                     pingId
            )
            context.insert(event)
            try? context.save()
        }
    }

    // MARK: - Persisted dedup helpers (Correction 3)

    private func isOutcomeAlreadyLogged(kind: String, identifier: String) -> Bool {
        let key = "notifOutcomeLogged.\(kind).\(identifier)"
        outcomeLock.lock()
        defer { outcomeLock.unlock() }
        if loggedOutcomeKeys.contains(key) { return true }
        let persisted = UserDefaults(suiteName: appGroupId)?.bool(forKey: key) ?? false
        if persisted { loggedOutcomeKeys.insert(key) }
        return persisted
    }

    private func markOutcomeLogged(kind: String, identifier: String) {
        let key = "notifOutcomeLogged.\(kind).\(identifier)"
        outcomeLock.lock()
        defer { outcomeLock.unlock() }
        loggedOutcomeKeys.insert(key)
        UserDefaults(suiteName: appGroupId)?.set(true, forKey: key)
    }

    // MARK: - Legacy non-ping outcome logging

    private struct NotificationPayload {
        let notificationId: String
        let kind: String
        let isTest: Bool
    }

    private func notificationPayload(from notification: UNNotification) -> NotificationPayload {
        let userInfo       = notification.request.content.userInfo
        let notificationId = (userInfo["notificationId"] as? String)
            ?? notification.request.identifier
        let kind   = (userInfo["kind"] as? String) ?? inferKind(notificationId: notificationId)
        let isTest = boolValue(userInfo["isTest"]) ?? (kind == "test_nudge")
        return NotificationPayload(notificationId: notificationId, kind: kind, isTest: isTest)
    }

    private func inferKind(notificationId: String) -> String {
        notificationId.hasPrefix("interrupt_ping_") ? "interruptibility_ping" : "unknown"
    }

    private func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool:   return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            let lower = s.lowercased()
            if ["true", "1", "yes"].contains(lower)  { return true }
            if ["false", "0", "no"].contains(lower) { return false }
            return nil
        default: return nil
        }
    }

    private func shouldLogOutcome(eventType: String, notificationId: String) -> Bool {
        let key = "\(eventType)|\(notificationId)"
        outcomeLock.lock()
        defer { outcomeLock.unlock() }
        if loggedOutcomeKeys.contains(key) {
            print("[NotificationDebug] duplicate outcome detected eventType=\(eventType) notificationId=\(notificationId)")
            return false
        }
        loggedOutcomeKeys.insert(key)
        return true
    }

    private func logOutcome(
        eventType: String,
        payload: NotificationPayload,
        actionId: String? = nil,
        modeRawOverride: String? = nil,
        extraMetadata: [String: Any] = [:]
    ) {
        guard let modelContainer = modelContainer else { return }
        guard shouldLogOutcome(eventType: eventType, notificationId: payload.notificationId) else { return }

        let modeRaw = modeRawOverride
            ?? UserDefaults.standard.string(forKey: "experimentMode")
            ?? ExperimentMode.baseline.rawValue

        var metadata: [String: Any] = [
            "notificationId": payload.notificationId,
            "kind":           payload.kind,
            "isTest":         payload.isTest
        ]
        extraMetadata.forEach { metadata[$0.key] = $0.value }
        if let actionId { metadata["actionId"] = actionId }

        let metadataJson: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let json = String(data: data, encoding: .utf8) {
            metadataJson = json
        } else {
            metadataJson = "{}"
        }

        DispatchQueue.main.async {
            let context = modelContainer.mainContext
            let event = TelemetryEvent(
                eventId:      UUID().uuidString,
                timestamp:    Date(),
                mode:         modeRaw,
                module:       "notifications",
                eventType:    eventType,
                sessionId:    UUID().uuidString,
                metadataJson: metadataJson
            )
            context.insert(event)
            try? context.save()

            switch eventType {
            case "notif_scheduled": print("[NotificationDebug] notification scheduled id=\(payload.notificationId) mode=\(modeRaw) kind=\(payload.kind)")
            case "notif_presented": print("[NotificationDebug] notification presented id=\(payload.notificationId)")
            case "notif_opened":    print("[NotificationDebug] notification opened id=\(payload.notificationId)")
            default: break
            }
        }
    }
}
