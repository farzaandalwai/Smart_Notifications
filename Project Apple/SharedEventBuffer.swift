//
//  SharedEventBuffer.swift
//  Project Apple
//

import Foundation

struct BufferedEvent: Codable {
    let eventId: String
    let timestampISO: String
    let sourceApp: String
    let eventType: String
    let modeRaw: String?
    let metadata: [String: String]
}

enum SharedEventBuffer {
    static let appGroupId = "group.com.farzaan.projectapple"
    private static let fileName = "appopen_events.jsonl"

    static func appendAppOpen(appName: String) {
        let timestamp = ISO8601DateHelper.encodeISO(Date())
        let event = BufferedEvent(
            eventId: UUID().uuidString,
            timestampISO: timestamp,
            sourceApp: appName,
            eventType: "app_opened",
            modeRaw: nil,
            metadata: [
                "sourceApp": appName,
                "timestampISO": timestamp
            ]
        )

        append(event: event)
    }

    static func appendAppClose(appName: String) {
        let timestamp = ISO8601DateHelper.encodeISO(Date())
        let event = BufferedEvent(
            eventId: UUID().uuidString,
            timestampISO: timestamp,
            sourceApp: appName,
            eventType: "app_closed",
            modeRaw: nil,
            metadata: [
                "sourceApp": appName,
                "timestampISO": timestamp
            ]
        )

        append(event: event)
    }

    // Unified ping response event. Replaces the old appendInterruptibilityLabel +
    // appendNotificationLifecycleEvent("notif_opened") pair.
    // label: "yes" | "no" | "not_now"
    // responseSource: "action_button" | "in_app_prompt"
    static func appendInterruptibilityResponse(
        label: String,
        notificationId: String,
        responseSource: String,
        scheduledAtISO: String? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        let timestamp = ISO8601DateHelper.encodeISO(Date())
        let modeRaw = UserDefaults(suiteName: appGroupId)?
            .string(forKey: "experimentMode")
            ?? UserDefaults.standard.string(forKey: "experimentMode")

        var metadata: [String: String] = [
            "label":                         label,
            "notificationId":                notificationId,
            "responseSource":                responseSource,
            "timestampISO":                  timestamp,
            // Correction 4: explicit responses carry confidence and override fields so the
            // data is present in metadataJson when these buffered events are imported.
            "outcomeConfidence":             "explicit",
            "explicitResponseOverride":      label,
            "notificationRequestIdentifier": notificationId
        ]
        if let scheduledAtISO {
            metadata["scheduledAtISO"] = scheduledAtISO
        }
        for (key, value) in additionalMetadata {
            metadata[key] = value
        }

        let event = BufferedEvent(
            eventId: UUID().uuidString,
            timestampISO: timestamp,
            sourceApp: "esm_notification",
            eventType: "interruptibility_response",
            modeRaw: modeRaw,
            metadata: metadata
        )

        append(event: event)
    }

    static func appendNotificationLifecycleEvent(
        eventType: String,
        notificationId: String,
        kind: String,
        isTest: Bool,
        modeRaw: String? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        let timestamp = ISO8601DateHelper.encodeISO(Date())
        let resolvedModeRaw = modeRaw
            ?? UserDefaults(suiteName: appGroupId)?.string(forKey: "experimentMode")
            ?? UserDefaults.standard.string(forKey: "experimentMode")

        var metadata: [String: String] = [
            "notificationId": notificationId,
            "notifId": notificationId,
            "kind": kind,
            "isTest": isTest ? "true" : "false",
            "timestampISO": timestamp
        ]
        for (key, value) in additionalMetadata {
            metadata[key] = value
        }

        let event = BufferedEvent(
            eventId: UUID().uuidString,
            timestampISO: timestamp,
            sourceApp: "notifications",
            eventType: eventType,
            modeRaw: resolvedModeRaw,
            metadata: metadata
        )
        append(event: event)
    }

    static func setInterruptibilityNotNowCooldown(hours: Double = 2) {
        let notNowUntil = Date().addingTimeInterval(hours * 3600).timeIntervalSince1970
        let defaults = UserDefaults(suiteName: appGroupId)
        defaults?.set(notNowUntil, forKey: "interruptibilityPing.notNowUntilEpoch")
    }

    static func drain() -> [BufferedEvent] {
        guard let url = bufferFileURL() else {
            return []
        }

        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty else {
            return []
        }

        let lines = content.split(separator: "\n")
        var events: [BufferedEvent] = []
        events.reserveCapacity(lines.count)

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(BufferedEvent.self, from: lineData) else {
                continue
            }
            events.append(event)
        }

        _ = try? Data().write(to: url, options: .atomic)
        return events
    }

    private static func bufferFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            return nil
        }

        return containerURL.appendingPathComponent(fileName)
    }

    private static func append(line: String, to url: URL) {
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            }
        } else {
            _ = try? data.write(to: url, options: .atomic)
        }
    }

    private static func append(event: BufferedEvent) {
        guard let data = try? JSONEncoder().encode(event),
              var line = String(data: data, encoding: .utf8) else {
            return
        }

        line.append("\n")

        guard let url = bufferFileURL() else {
            return
        }

        append(line: line, to: url)
    }
}
