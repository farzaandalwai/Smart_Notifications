//
//  NotificationOutcomeConfig.swift
//  Project Apple
//
//  Centralized configuration for notification outcome analytics.
//  Change `trustedNotificationOutcomeStartDate` to adjust the cutoff for all
//  notification outcome aggregation (scheduled / presented / opened / open rate /
//  median latency). Only notification outcome analytics are affected — all other
//  telemetry (app_opened, app_closed, sessions, interruptibility_label, raw events,
//  Firebase sync) are completely unaffected.
//

import Foundation

enum NotificationOutcomeConfig {
    // Pipeline-fix date: March 8, 2026.
    // Events before this date may contain pre-fix test nudges without `isTest` metadata
    // and should not be included in experiment analytics or training data.
    // To adjust: change the date components below.
    static let trustedNotificationOutcomeStartDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = .current
        return Calendar.current.date(from: components) ?? Date.distantPast
    }()
}
