//
//  AnalyticsView.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import SwiftUI
import SwiftData

struct AnalyticsView: View {
    // One row in the Ping Responses list.
    private struct PingResponseRow: Identifiable {
        let id: String         // notificationId
        let respondedAt: Date
        let label: String      // "yes" | "no" | "not_now"
        let responseSource: String  // "action_button" | "in_app_prompt"
        let responseDelaySec: TimeInterval?  // nil if no matching ping_sent

        var labelDisplay: String {
            switch label {
            case "yes": return "Yes"
            case "no": return "No"
            case "not_now": return "Not now"
            default: return label
            }
        }
    }

    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue
    @Environment(\.modelContext) private var modelContext: ModelContext
    @Query(sort: \TelemetryEvent.timestamp, order: .reverse) private var events: [TelemetryEvent]
    @Query(sort: \AppSession.startTime, order: .reverse) private var sessions: [AppSession]

    @State private var isRebuildingSessions = false
    @State private var isSyncingNow = false
    @State private var firebaseUid = "-"
    @State private var lastSyncStatus = "idle"
    @State private var lastSyncError = ""
    @State private var lastSyncedAtISO = "-"

    private let appGroupId = "group.com.farzaan.projectapple"

    private var experimentMode: ExperimentMode {
        ExperimentMode(rawValue: experimentModeRaw) ?? .baseline
    }

    private var experimentModeBinding: Binding<ExperimentMode> {
        Binding(
            get: { experimentMode },
            set: { experimentModeRaw = $0.rawValue }
        )
    }

    private var recentEvents: [TelemetryEvent] {
        Array(events.prefix(20))
    }

    private var eventTypeSummary: [(eventType: String, count: Int)] {
        let counts = Dictionary(grouping: events, by: \.eventType)
            .map { (eventType: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.eventType < rhs.eventType
                }
                return lhs.count > rhs.count
            }
        return Array(counts.prefix(10))
    }

    private var recentSessions: [AppSession] {
        Array(sessions.prefix(10))
    }

    // MARK: - Ping Responses

    private var pingSentEvents: [TelemetryEvent] {
        events.filter { $0.eventType == "ping_sent" }
    }

    private var pingResponseEvents: [TelemetryEvent] {
        events.filter { $0.eventType == "interruptibility_response" }
    }

    // Decode "scheduledForISO" from a ping_sent event's metadataJson.
    private func scheduledForISO(from event: TelemetryEvent) -> String? {
        guard let data = event.metadataJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["scheduledForISO"] as? String
    }

    // Decode a string field from any event's metadataJson.
    private func metadataString(_ key: String, from event: TelemetryEvent) -> String? {
        guard let data = event.metadataJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json[key] as? String
    }

    private var pingResponseRows: [PingResponseRow] {
        // Build a lookup: notificationId → ping_sent timestamp or scheduledForISO
        var sentTimeById: [String: Date] = [:]
        for sent in pingSentEvents {
            guard let notifId = metadataString("notificationId", from: sent) else { continue }
            // Prefer the scheduledForISO field (actual fire time) over the log timestamp
            if let isoStr = scheduledForISO(from: sent),
               let date = ISO8601DateHelper.decodeISO(isoStr) {
                if sentTimeById[notifId] == nil { sentTimeById[notifId] = date }
            } else if sentTimeById[notifId] == nil {
                sentTimeById[notifId] = sent.timestamp
            }
        }

        return pingResponseEvents.compactMap { response in
            guard let notifId = metadataString("notificationId", from: response) else { return nil }
            let label = metadataString("label", from: response) ?? "unknown"
            let source = metadataString("responseSource", from: response) ?? "unknown"
            let delay: TimeInterval? = sentTimeById[notifId].map {
                response.timestamp.timeIntervalSince($0)
            }
            return PingResponseRow(
                id: notifId + "_" + response.eventId,
                respondedAt: response.timestamp,
                label: label,
                responseSource: source,
                responseDelaySec: delay
            )
        }.sorted { $0.respondedAt > $1.respondedAt }
    }

    private var pingResponseRate: Double {
        guard !pingSentEvents.isEmpty else { return 0 }
        let respondedIds = Set(pingResponseEvents.compactMap { metadataString("notificationId", from: $0) })
        let sentIds = Set(pingSentEvents.compactMap { metadataString("notificationId", from: $0) })
        return (Double(respondedIds.intersection(sentIds).count) / Double(sentIds.count)) * 100
    }

    private var pingLabelCounts: (yes: Int, no: Int, notNow: Int) {
        let responses = pingResponseEvents
        let yes = responses.filter { metadataString("label", from: $0) == "yes" }.count
        let no = responses.filter { metadataString("label", from: $0) == "no" }.count
        let notNow = responses.filter { metadataString("label", from: $0) == "not_now" }.count
        return (yes, no, notNow)
    }

    // MARK: - Sessions

    private var topAppsByTime: [(app: String, totalTime: Double)] {
        let grouped = Dictionary(grouping: sessions, by: { $0.appName })
        let totals = grouped.mapValues { sessions in
            sessions.reduce(0.0) { $0 + $1.durationSec }
        }
        return totals
            .sorted { $0.value > $1.value }
            .map { (app: $0.key, totalTime: $0.value) }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
    
    private func rebuildSessions() {
        isRebuildingSessions = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Sessionizer.rebuildSessions(context: modelContext)
            isRebuildingSessions = false
        }
    }

    private func refreshCloudSyncStatus() {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        firebaseUid = defaults.string(forKey: "firebaseUid") ?? "-"
        lastSyncStatus = defaults.string(forKey: "lastSyncStatus") ?? "idle"
        lastSyncError = defaults.string(forKey: "lastSyncError") ?? ""
        lastSyncedAtISO = defaults.string(forKey: "lastSyncedAtISO") ?? "-"
    }

    private func triggerCloudSync() {
        isSyncingNow = true
        Task {
            await CloudSyncManager.shared.syncNow(modelContext: modelContext)
            await MainActor.run {
                isSyncingNow = false
                refreshCloudSyncStatus()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Analytics")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("Mode: \(experimentMode.displayName)")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Picker("Experiment Mode", selection: experimentModeBinding) {
                    ForEach(ExperimentMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

#if DEBUG
                InterruptibilityDebugCard()
#endif

                VStack(alignment: .leading, spacing: 12) {
                    Text("Cloud Sync")
                        .font(.headline)

                    HStack {
                        Button(action: triggerCloudSync) {
                            if isSyncingNow {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sync Now")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSyncingNow)

                        Spacer()
                    }

                    Text("UID: \(firebaseUid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Status: \(lastSyncStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Last Synced At: \(lastSyncedAtISO)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !lastSyncError.isEmpty {
                        Text("Error: \(lastSyncError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // MARK: Ping Responses — unified section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ping Responses")
                        .font(.headline)

                    let counts = pingLabelCounts
                    let respondedCount = counts.yes + counts.no + counts.notNow

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sent")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(pingSentEvents.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Responded")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(respondedCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rate")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", pingResponseRate))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }

                    HStack {
                        Label("\(counts.yes) Yes", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                        Label("\(counts.no) No", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Label("\(counts.notNow) Not now", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    let rows = Array(pingResponseRows.prefix(10))
                    if rows.isEmpty {
                        Text("No responses yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(rows) { row in
                                HStack(spacing: 6) {
                                    Text(row.respondedAt, format: .dateTime.hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(row.labelDisplay)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(row.label == "yes" ? .green : (row.label == "no" ? .red : .secondary))
                                    Text(row.responseSource == "in_app_prompt" ? "in-app" : "notif")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let delay = row.responseDelaySec, delay >= 0 {
                                        Text(formatDuration(delay))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Event Types Summary")
                        .font(.headline)

                    if eventTypeSummary.isEmpty {
                        Text("No event types yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(eventTypeSummary, id: \.eventType) { item in
                                HStack {
                                    Text(item.eventType)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Session Analytics Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sessions")
                        .font(.headline)
                    
                    HStack {
                        Text("Total sessions: \(sessions.count)")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Button(action: rebuildSessions) {
                            if isRebuildingSessions {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Rebuild Sessions")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRebuildingSessions)
                    }
                    
                    if !topAppsByTime.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top Apps by Time")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            ForEach(topAppsByTime.prefix(5), id: \.app) { item in
                                HStack {
                                    Text(item.app)
                                        .font(.caption)
                                    Spacer()
                                    Text(formatDuration(item.totalTime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if !recentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Sessions")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            ForEach(recentSessions, id: \.sessionId) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.appName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(session.startTime, format: .dateTime.hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(formatDuration(session.durationSec))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                
                // Events Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Raw Events")
                        .font(.headline)
                    
                    Text("Total events: \(events.count)")
                        .font(.subheadline)

#if DEBUG
                    Button("Log Test Event") {
                        TelemetryLogger.log(
                            context: modelContext,
                            mode: experimentMode,
                            module: .analytics,
                            eventType: "analytics_test_tap"
                        )
                    }
                    .buttonStyle(.bordered)
#endif

                    if recentEvents.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recentEvents, id: \.id) { event in
                                HStack(spacing: 8) {
                                    Text(event.timestamp, format: .dateTime.hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(event.module) \(event.eventType)")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .onAppear {
            refreshCloudSyncStatus()
        }
    }
}

#Preview {
    AnalyticsView()
}
