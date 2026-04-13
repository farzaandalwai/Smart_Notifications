//
//  RootTabView.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import SwiftUI
import SwiftData

enum ExperimentMode: String, CaseIterable, Identifiable {
    case baseline
    case smart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baseline:
            return "Baseline"
        case .smart:
            return "Smart"
        }
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue

    @State private var pendingPingId: String?
    @State private var showPingAlert = false

    private var experimentMode: ExperimentMode {
        ExperimentMode(rawValue: experimentModeRaw) ?? .baseline
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            LiveView()
                .tabItem {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }

            VoiceView()
                .tabItem {
                    Label("Voice", systemImage: "mic")
                }

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
        }
        .onAppear {
            checkPendingPing()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkPendingPing()
            }
        }
        .alert("Are you interruptible?", isPresented: $showPingAlert) {
            Button("Yes") { respondToPing(label: "yes") }
            Button("No") { respondToPing(label: "no") }
            Button("Not now", role: .cancel) { respondToPing(label: "not_now") }
        } message: {
            Text("Quick check-in — are you free to be interrupted right now?")
        }
    }

    private func checkPendingPing() {
        guard let pingId = AppNotificationCenterDelegate.shared.pendingPingId else { return }
        pendingPingId = pingId
        AppNotificationCenterDelegate.shared.pendingPingId = nil
        showPingAlert = true
        print("[PingDebug] showing in-app prompt for pendingPingId=\(pingId)")
    }

    private func respondToPing(label: String) {
        guard let pingId = pendingPingId else { return }
        let deviceSnapshot = DeviceContextCollector.snapshot(appGroupId: SharedEventBuffer.appGroupId)
        let deviceMetadata: [String: String] = [
            "device_batteryBucket": deviceSnapshot["batteryBucket"] ?? "unknown",
            "device_isCharging": deviceSnapshot["isCharging"] ?? "unknown",
            "device_lowPowerMode": deviceSnapshot["lowPowerMode"] ?? "0",
            "device_audioPlaying": deviceSnapshot["audioPlaying"] ?? "0",
            "device_networkType": deviceSnapshot["networkType"] ?? "unknown"
        ]

        var metadata: [String: Any] = [
            "notificationId": pingId,
            "label": label,
            "responseSource": "in_app_prompt"
        ]
        for (key, value) in deviceMetadata {
            metadata[key] = value
        }

        // Correction 4: explicit in-app responses are logged as separate events with explicit confidence,
        // linked to the originating ping by notificationRequestIdentifier / pingId.
        TelemetryLogger.log(
            context: modelContext,
            mode: experimentMode,
            module: .notifications,
            eventType: "interruptibility_response",
            metadata: metadata,
            outcomeConfidence: .explicit,
            notificationRequestIdentifier: pingId,
            pingId: pingId,
            explicitResponseOverride: label
        )
        InterruptibilityPingScheduler.markPendingEntryExplicitResponseLogged(identifier: pingId)

        if label == "not_now" {
            SharedEventBuffer.setInterruptibilityNotNowCooldown(hours: 2)
            InterruptibilityPingScheduler.applyNotNowCooldown(hours: 2)
        }

        print("[PingDebug] in-app response label=\(label) notificationId=\(pingId)")
        pendingPingId = nil
    }
}

#Preview {
    RootTabView()
}
