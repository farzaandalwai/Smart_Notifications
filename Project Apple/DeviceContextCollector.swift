//
//  DeviceContextCollector.swift
//  Project Apple
//

import AVFoundation
import Foundation
import UIKit

enum DeviceContextCollector {
    static func snapshot(appGroupId: String) -> [String: String] {
        let batteryBucket = resolveBatteryBucket()
        let isCharging = resolveCharging()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled ? "1" : "0"
        let audioPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying ? "1" : "0"
        let networkType = UserDefaults(suiteName: appGroupId)?
            .string(forKey: "latestNetwork") ?? "unknown"

        let snapshot: [String: String] = [
            "batteryBucket": batteryBucket,
            "isCharging": isCharging,
            "lowPowerMode": lowPowerMode,
            "audioPlaying": audioPlaying,
            "networkType": networkType
        ]

        return snapshot
    }

    private static func resolveBatteryBucket() -> String {
        let device = UIDevice.current
        let prior = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = prior }

        let level = device.batteryLevel
        guard level >= 0 else { return "unknown" }
        let pct = level * 100
        switch pct {
        case 0..<20: return "0-20"
        case 20..<50: return "20-50"
        case 50..<80: return "50-80"
        default: return "80-100"
        }
    }

    private static func resolveCharging() -> String {
        let device = UIDevice.current
        let prior = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = prior }

        switch device.batteryState {
        case .charging, .full: return "1"
        case .unplugged: return "0"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
