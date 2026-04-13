//
//  CloudSyncManager.swift
//  Project Apple
//

import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
final class CloudSyncManager {
    static let shared = CloudSyncManager()

    private let appGroupId = "group.com.farzaan.projectapple"
    private let lastSyncedAtISOKey = "lastSyncedAtISO"
    private let lastSyncStatusKey = "lastSyncStatus"
    private let lastSyncErrorKey = "lastSyncError"
    private let initialSyncLimit = 200

    private init() {}

    func syncNow(modelContext: ModelContext) async {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        defaults.set("syncing", forKey: lastSyncStatusKey)
        defaults.set("", forKey: lastSyncErrorKey)

        do {
            let uid = try await AuthManager.shared.ensureSignedIn()
            let events = try fetchEventsToSync(modelContext: modelContext)

            guard !events.isEmpty else {
                defaults.set("idle_no_new_events", forKey: lastSyncStatusKey)
                return
            }

            let db = Firestore.firestore()

            // Firestore batches are capped at 500 operations; use 400 as the safe ceiling.
            let chunkSize = 400
            let chunks = stride(from: 0, to: events.count, by: chunkSize).map {
                Array(events[$0 ..< min($0 + chunkSize, events.count)])
            }

            for chunk in chunks {
                let batch = db.batch()
                for event in chunk {
                    let docRef = db.collection("telemetry_events")
                        .document(uid)
                        .collection("events")
                        .document(event.eventId)
                    batch.setData(firestoreData(for: event), forDocument: docRef, merge: false)
                }
                try await commit(batch: batch)
            }

            if let maxTimestamp = events.map(\.timestamp).max() {
                let cursorISO = ISO8601DateHelper.encodeISO(maxTimestamp)
                defaults.set(cursorISO, forKey: lastSyncedAtISOKey)
            }
            defaults.set("success", forKey: lastSyncStatusKey)
            defaults.set("", forKey: lastSyncErrorKey)
        } catch {
            defaults.set("failed", forKey: lastSyncStatusKey)
            defaults.set(error.localizedDescription, forKey: lastSyncErrorKey)
        }
    }

    private func fetchEventsToSync(modelContext: ModelContext) throws -> [TelemetryEvent] {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        let lastSyncedAtISO = defaults.string(forKey: lastSyncedAtISOKey)

        if let lastSyncedAtISO,
           let cursorDate = ISO8601DateHelper.decodeISO(lastSyncedAtISO) {
            let descriptor = FetchDescriptor<TelemetryEvent>(
                predicate: #Predicate { $0.timestamp > cursorDate },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            return try modelContext.fetch(descriptor)
        } else {
            var descriptor = FetchDescriptor<TelemetryEvent>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = initialSyncLimit
            let fetched = try modelContext.fetch(descriptor)
            return fetched.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private func firestoreData(for event: TelemetryEvent) -> [String: Any] {
        var payload: [String: Any] = [
            "eventId": event.eventId,
            "timestampISO": ISO8601DateHelper.encodeISO(event.timestamp),
            "timestampMs": Int(event.timestamp.timeIntervalSince1970 * 1000),
            "eventType": event.eventType,
            "sourceModule": event.module,
            "experimentMode": displayMode(event.mode),
            "modeRaw": event.mode,
            "sessionId": event.sessionId
        ]

        if let metadata = parseMetadataJson(event.metadataJson), !metadata.isEmpty {
            payload["metadata"] = metadata
        } else {
            payload["metadata"] = [:]
        }

        // New optional notification-outcome fields — omitted for legacy events where they are nil.
        if let v = event.notificationOutcome          { payload["notificationOutcome"]          = v }
        if let v = event.outcomeConfidence            { payload["outcomeConfidence"]             = v }
        if let v = event.actualDeliveryTimestampISO   { payload["actualDeliveryTimestampISO"]    = v }
        if let v = event.notificationRequestIdentifier { payload["notificationRequestIdentifier"] = v }
        if let v = event.pingId                       { payload["pingId"]                        = v }
        if let v = event.explicitResponseOverride     { payload["explicitResponseOverride"]      = v }

        return payload
    }

    private func displayMode(_ raw: String) -> String {
        if raw == ExperimentMode.baseline.rawValue { return "Baseline" }
        if raw == ExperimentMode.smart.rawValue { return "Smart" }
        return raw
    }

    private func parseMetadataJson(_ jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func commit(batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
