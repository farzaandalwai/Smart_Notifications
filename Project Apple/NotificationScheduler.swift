//
//  NotificationScheduler.swift
//  Project Apple
//

import Foundation
import SwiftData
import UserNotifications

enum NotificationPolicy: String {
    case baseline
    case smart
}

struct NotificationScheduler {
    private static let baselineDelaySec = 10
    private static let smartYesDelaySec = 10
    private static let smartNoDelaySec = 120
    private static let smartUnknownDelaySec = 60

    static func scheduleNudge(
        context: ModelContext,
        mode: ExperimentMode,
        forcedPolicy: NotificationPolicy? = nil,
        reason: String
    ) {
        let policy = forcedPolicy ?? (mode == .smart ? .smart : .baseline)
        let fireInSeconds = fireDelaySeconds(policy: policy, context: context)
        let notificationId = UUID().uuidString
        let isTest = reason.localizedCaseInsensitiveContains("test")
        let kind: String
        if isTest {
            kind = "test_nudge"
        } else if policy == .smart {
            kind = "smart_nudge"
        } else {
            kind = "baseline_nudge"
        }

        let content = UNMutableNotificationContent()
        content.title = "Quick check-in"
        content.body = "Are you interruptible right now?"
        content.sound = .default
        content.userInfo = [
            "notificationId": notificationId,
            "policy": policy.rawValue,
            "kind": kind,
            "isTest": isTest
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(fireInSeconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        let deviceContext = DeviceContextCollector.snapshot(appGroupId: SharedEventBuffer.appGroupId)
        var metadata: [String: Any] = [
            "notificationId": notificationId,
            "policy": policy.rawValue,
            "kind": kind,
            "isTest": isTest,
            "fireInSeconds": fireInSeconds,
            "reason": reason
        ]
        metadata["device_batteryBucket"] = deviceContext["batteryBucket"] ?? "unknown"
        metadata["device_isCharging"] = deviceContext["isCharging"] ?? "unknown"
        metadata["device_lowPowerMode"] = deviceContext["lowPowerMode"] ?? "0"
        metadata["device_audioPlaying"] = deviceContext["audioPlaying"] ?? "0"
        metadata["device_networkType"] = deviceContext["networkType"] ?? "unknown"

        TelemetryLogger.log(
            context: context,
            mode: mode,
            module: .notifications,
            eventType: "notif_scheduled",
            metadata: metadata,
            notificationRequestIdentifier: notificationId
        )
        try? context.save()
        print("[NotificationDebug] notification scheduled id=\(notificationId) mode=\(mode.rawValue) kind=\(kind)")
    }

    private static func fireDelaySeconds(policy: NotificationPolicy, context: ModelContext) -> Int {
        switch policy {
        case .baseline:
            return baselineDelaySec
        case .smart:
            guard let label = latestInterruptibilityLabel(context: context) else {
                return smartUnknownDelaySec
            }
            return label == "1" ? smartYesDelaySec : smartNoDelaySec
        }
    }

    private static func latestInterruptibilityLabel(context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<TelemetryEvent>(
            predicate: #Predicate { $0.eventType == "interruptibility_label" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let latest = try? context.fetch(descriptor).first else {
            return nil
        }

        guard let data = latest.metadataJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let label = json["label"] as? String else {
            return nil
        }
        return label
    }
}
