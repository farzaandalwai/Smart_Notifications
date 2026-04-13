//
//  Project_AppleApp.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct Project_AppleApp: App {
    private let networkStateMonitor = NetworkStateMonitor.shared

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        networkStateMonitor.start(appGroupId: SharedEventBuffer.appGroupId)
        AppNotificationCenterDelegate.shared.configure(modelContainer: sharedModelContainer)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            TelemetryEvent.self,
            AppSession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppLaunchImportView(modelContainer: sharedModelContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}

private struct AppLaunchImportView: View {
    let modelContainer: ModelContainer

    @Environment(\.modelContext) private var modelContext: ModelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue

    private var modeForStorage: String {
        ExperimentMode(rawValue: experimentModeRaw)?.rawValue ?? "unknown"
    }

    var body: some View {
        RootTabView()
            .onAppear {
                importBufferedEvents()
                syncInterruptibilityPingSchedule()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    importBufferedEvents()
                    syncInterruptibilityPingSchedule()
                }
            }
    }

    private func importBufferedEvents() {
        let bufferedEvents = SharedEventBuffer.drain()
        guard !bufferedEvents.isEmpty else {
            return
        }

        // Fetch existing eventIds to dedupe
        let existingIds = fetchExistingEventIds()

        for event in bufferedEvents {
            // Skip if already imported
            guard !existingIds.contains(event.eventId) else {
                continue
            }

            // Parse timestamp from ISO string
            guard let timestamp = ISO8601DateHelper.decodeISO(event.timestampISO) else {
                print("⚠️ Failed to parse timestampISO: \(event.timestampISO), skipping event")
                continue
            }

            var metadata = event.metadata
            metadata["sourceApp"] = metadata["sourceApp"] ?? event.sourceApp
            metadata["timestampISO"] = metadata["timestampISO"] ?? event.timestampISO
            let metadataJson = encodeMetadata(metadata)

            let telemetryEvent = TelemetryEvent(
                eventId: event.eventId,
                timestamp: timestamp,
                mode: event.modeRaw ?? modeForStorage,
                module: event.sourceApp,
                eventType: event.eventType,
                sessionId: UUID().uuidString,
                metadataJson: metadataJson
            )

            modelContext.insert(telemetryEvent)
        }

        do {
            try modelContext.save()
        } catch {
            print("Import save failed: \(error.localizedDescription)")
        }

        // Auto-sessionize after importing new events
        Sessionizer.sessionize(context: modelContext)

        // Best-effort ignored-ping reconciliation.
        // Runs on every app foreground (BGTaskScheduler not registered in this project).
        // reconcileIgnoredPings is @MainActor and importBufferedEvents runs on the main actor,
        // so this call is safe without an explicit actor hop.
        InterruptibilityPingScheduler.reconcileIgnoredPings(context: modelContext)
    }

    private func fetchExistingEventIds() -> Set<String> {
        let descriptor = FetchDescriptor<TelemetryEvent>()
        guard let events = try? modelContext.fetch(descriptor) else {
            return []
        }
        return Set(events.map(\.eventId))
    }

    private func encodeMetadata(_ metadata: [String: String]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    private func syncInterruptibilityPingSchedule() {
        guard InterruptibilityPingScheduler.isEnabled() else { return }
        InterruptibilityPingScheduler.ensurePingsScheduled()
    }
}
