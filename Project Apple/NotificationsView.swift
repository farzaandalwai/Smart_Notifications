//
//  NotificationsView.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pingsEnabled: Bool = false
    @State private var nextScheduledPing: Date?

    private var experimentMode: ExperimentMode {
        ExperimentMode(rawValue: experimentModeRaw) ?? .baseline
    }

    private var authorizationStatusText: String {
        switch authorizationStatus {
        case .notDetermined: return "Not determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Notifications")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Mode: \(experimentMode.displayName)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Permission: \(authorizationStatusText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Enable Notifications") {
                requestNotificationPermission()
            }
            .buttonStyle(.borderedProminent)

            Toggle("Enable Interruptibility Pings", isOn: Binding(
                get: { pingsEnabled },
                set: { newValue in
                    pingsEnabled = newValue
                    InterruptibilityPingScheduler.setEnabled(newValue)
                    if newValue {
                        InterruptibilityPingScheduler.ensurePingsScheduled()
                    } else {
                        InterruptibilityPingScheduler.clearPendingPings()
                    }
                    refreshNextScheduledPingAfterDelay()
                }
            ))
            .padding(.top, 4)

            if let nextScheduledPing {
                Text("Next ping: \(nextScheduledPing, format: .dateTime.month().day().hour().minute())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Next ping: none scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            Button("Clear Pending Pings") {
                InterruptibilityPingScheduler.clearPendingPings()
                refreshNextScheduledPingAfterDelay()
            }
            .buttonStyle(.bordered)

#endif
            Text("Pings are scheduled automatically each day between noon and midnight.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            refreshAuthorizationStatus()
            pingsEnabled = InterruptibilityPingScheduler.isEnabled()
            if pingsEnabled {
                InterruptibilityPingScheduler.ensurePingsScheduled()
            }
            refreshNextScheduledPing()
        }
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted && pingsEnabled {
                InterruptibilityPingScheduler.ensurePingsScheduled()
            }
            refreshAuthorizationStatus()
            refreshNextScheduledPingAfterDelay()
        }
    }

    private func refreshNextScheduledPing() {
        InterruptibilityPingScheduler.nextScheduledPing { date in
            DispatchQueue.main.async {
                nextScheduledPing = date
            }
        }
    }

    private func refreshNextScheduledPingAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            refreshNextScheduledPing()
        }
    }
}

#Preview {
    NotificationsView()
}
