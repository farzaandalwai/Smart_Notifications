//
//  InterruptibilityPingScheduler.swift
//  Project Apple
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - Pending ping metadata

/// Persisted per-ping record written at schedule time and enriched as the ping lifecycle progresses.
struct PendingPingEntry: Codable {
    let requestIdentifier: String
    let scheduledForISO: String
    let modeRaw: String
    var actualDeliveryISO: String?       // written by willPresent (foreground) or left nil for background delivery
    var outcomeLogged: String?           // "opened" | "dismissed" | "ignored" — set once to prevent double-logging
    var explicitResponseLogged: Bool     // true when yes/no/not_now has been recorded for this ping

    init(
        requestIdentifier: String,
        scheduledForISO: String,
        modeRaw: String,
        actualDeliveryISO: String? = nil,
        outcomeLogged: String? = nil,
        explicitResponseLogged: Bool = false
    ) {
        self.requestIdentifier     = requestIdentifier
        self.scheduledForISO       = scheduledForISO
        self.modeRaw               = modeRaw
        self.actualDeliveryISO     = actualDeliveryISO
        self.outcomeLogged         = outcomeLogged
        self.explicitResponseLogged = explicitResponseLogged
    }

    // Custom decoder so existing UserDefaults entries that pre-date this field decode safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestIdentifier      = try c.decode(String.self,  forKey: .requestIdentifier)
        scheduledForISO        = try c.decode(String.self,  forKey: .scheduledForISO)
        modeRaw                = try c.decode(String.self,  forKey: .modeRaw)
        actualDeliveryISO      = try c.decodeIfPresent(String.self, forKey: .actualDeliveryISO)
        outcomeLogged          = try c.decodeIfPresent(String.self, forKey: .outcomeLogged)
        explicitResponseLogged = try c.decodeIfPresent(Bool.self,   forKey: .explicitResponseLogged) ?? false
    }
}

// MARK: - Scheduler

enum InterruptibilityPingScheduler {
    static let categoryId  = "INTERRUPTIBILITY_PING"
    static let actionYes   = "PING_YES"
    static let actionNo    = "PING_NO"
    static let actionNotNow = "PING_NOT_NOW"

    private static let appGroupId       = "group.com.farzaan.projectapple"
    private static let enabledKey       = "interruptibilityPing.enabled"
    private static let notNowUntilKey   = "interruptibilityPing.notNowUntilEpoch"
    private static let pendingEntriesKey = "interruptibilityPing.pendingEntries"
    private static let pingsPerDay      = 10
    private static let windowStartHour  = 6
    private static let minGapSeconds    = 60 * 60.0
    private static let idPrefix         = "interrupt_ping_"
    private static let ignoredThreshold: TimeInterval = 30 * 60
    private static let entryMaxAgeDays: TimeInterval  = 7 * 24 * 3600

    // MARK: Category registration

    static func registerCategory() {
        let actions = [
            UNNotificationAction(identifier: actionYes,    title: "Yes"),
            UNNotificationAction(identifier: actionNo,     title: "No"),
            UNNotificationAction(identifier: actionNotNow, title: "Not now")
        ]
        // .customDismissAction is required so UNUserNotificationCenterDelegate.didReceive fires
        // when the user swipes the notification away, enabling the "dismissed" outcome.
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: Enable / disable

    static func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func isEnabled() -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    // MARK: Schedule management

    static func ensurePingsScheduled() {
        guard isEnabled() else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let now        = Date()
                let calendar   = Calendar.current
                let todayStart = calendar.startOfDay(for: now)
                guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }

                let managed = requests.filter { $0.content.categoryIdentifier == categoryId }
                let keepStamps = Set([dayStamp(for: todayStart), dayStamp(for: tomorrowStart)])

                let staleIds = staleManagedIds(from: managed, keepDayStamps: keepStamps)
                if !staleIds.isEmpty {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIds)
                }

                let valid = managed.filter { !staleIds.contains($0.identifier) }
                let byDay = managedRequestsByDayAndIndex(from: valid)
                scheduleMissingPings(
                    forDayStart: todayStart,
                    now: now,
                    existingByIndex: byDay[dayStamp(for: todayStart)] ?? [:]
                )
                scheduleMissingPings(
                    forDayStart: tomorrowStart,
                    now: now,
                    existingByIndex: byDay[dayStamp(for: tomorrowStart)] ?? [:]
                )
            }
        }
    }

    static func clearPendingPings() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.content.categoryIdentifier == categoryId }
                .map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    static func nextScheduledPing(completion: @escaping (Date?) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let next = requests
                .filter { $0.content.categoryIdentifier == categoryId }
                .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
                .sorted()
                .first
            completion(next)
        }
    }

    static func applyNotNowCooldown(hours: Double = 2) {
        defaults.set(Date().addingTimeInterval(hours * 3600).timeIntervalSince1970, forKey: notNowUntilKey)
    }

    // MARK: - Pending Ping Store

    static func savePendingEntry(_ entry: PendingPingEntry) {
        var all = loadAllPendingEntries()
        all[entry.requestIdentifier] = entry
        persistEntries(all)
    }

    /// Called from willPresent (foreground delivery confirmed) to record the actual delivery date.
    static func updatePendingEntryDelivery(identifier: String, deliveryISO: String) {
        var all = loadAllPendingEntries()
        guard var entry = all[identifier] else { return }
        entry.actualDeliveryISO = deliveryISO
        all[identifier] = entry
        persistEntries(all)
    }

    /// Called after a passive outcome event is logged so reconciliation skips this ping.
    static func markPendingEntryOutcomeLogged(identifier: String, outcome: String) {
        var all = loadAllPendingEntries()
        guard var entry = all[identifier] else { return }
        entry.outcomeLogged = outcome
        all[identifier] = entry
        persistEntries(all)
    }

    /// Called after any yes / no / not_now response is recorded so ignored reconciliation skips this ping.
    static func markPendingEntryExplicitResponseLogged(identifier: String) {
        var all = loadAllPendingEntries()
        guard var entry = all[identifier] else { return }
        entry.explicitResponseLogged = true
        all[identifier] = entry
        persistEntries(all)
    }

    static func loadPendingEntry(identifier: String) -> PendingPingEntry? {
        loadAllPendingEntries()[identifier]
    }

    static func loadAllPendingEntries() -> [String: PendingPingEntry] {
        guard let data = defaults.data(forKey: pendingEntriesKey),
              let entries = try? JSONDecoder().decode([String: PendingPingEntry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private static func persistEntries(_ entries: [String: PendingPingEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: pendingEntriesKey)
    }

    /// Removes entries older than entryMaxAgeDays to prevent unbounded growth.
    private static func cleanupExpiredEntries() {
        var all = loadAllPendingEntries()
        let cutoff = Date().addingTimeInterval(-entryMaxAgeDays)
        let staleKeys = all.keys.filter { key in
            guard let entry = all[key],
                  let scheduled = ISO8601DateHelper.decodeISO(entry.scheduledForISO) else { return true }
            return scheduled < cutoff
        }
        guard !staleKeys.isEmpty else { return }
        staleKeys.forEach { all.removeValue(forKey: $0) }
        persistEntries(all)
    }

    // MARK: - Ignored Reconciliation

    /// Best-effort ignored-outcome reconciliation.
    /// Must be called on the MainActor (importBufferedEvents satisfies this).
    /// BGTaskScheduler is not registered in this project, so reconciliation runs on each app foreground.
    /// iOS does not guarantee exact 30-min execution; this is best-effort per the spec.
    @MainActor
    static func reconcileIgnoredPings(context: ModelContext) {
        cleanupExpiredEntries()
        Task { @MainActor in
            await performIgnoredReconciliation(context: context)
        }
    }

    @MainActor
    private static func performIgnoredReconciliation(context: ModelContext) async {
        let allEntries = loadAllPendingEntries()
        let now = Date()

        // Only consider pings that are past the ignored threshold, have no passive terminal outcome,
        // and have no explicit yes/no/not_now response already recorded.
        let candidates = allEntries.values.filter { entry in
            guard entry.outcomeLogged == nil else { return false }
            guard !entry.explicitResponseLogged else { return false }
            guard let scheduled = ISO8601DateHelper.decodeISO(entry.scheduledForISO) else { return false }
            return now.timeIntervalSince(scheduled) >= ignoredThreshold
        }
        guard !candidates.isEmpty else { return }

        // Ask the OS which notifications are still visible in Notification Centre
        let delivered = await withCheckedContinuation { (cont: CheckedContinuation<[UNNotification], Never>) in
            UNUserNotificationCenter.current().getDeliveredNotifications { cont.resume(returning: $0) }
        }
        let deliveredIds = Set(delivered.map { $0.request.identifier })

        for entry in candidates {
            let identifier = entry.requestIdentifier

            // Spec: only log ignored when the notification is still in Notification Centre
            guard deliveredIds.contains(identifier) else { continue }

            // Persisted dedup — survives relaunches
            let dedupKey = "notifOutcomeLogged.ignored.\(identifier)"
            guard !defaults.bool(forKey: dedupKey) else { continue }

            let deliveredNotif  = delivered.first { $0.request.identifier == identifier }
            let deliveryISO: String? = entry.actualDeliveryISO
                ?? deliveredNotif.map { ISO8601DateHelper.encodeISO($0.date) }

            let event = TelemetryEvent(
                eventId: "outcome_ignored_\(identifier)",
                timestamp: Date(),
                mode: entry.modeRaw,
                module: "notifications",
                eventType: "notification_outcome",
                sessionId: UUID().uuidString,
                metadataJson: "{}",
                notificationOutcome: NotificationOutcome.ignored.rawValue,
                outcomeConfidence: OutcomeConfidence.soft.rawValue,
                actualDeliveryTimestampISO: deliveryISO,
                notificationRequestIdentifier: identifier,
                pingId: identifier
            )
            context.insert(event)

            // Mark dedup in UserDefaults and pending store
            defaults.set(true, forKey: dedupKey)
            markPendingEntryOutcomeLogged(identifier: identifier, outcome: NotificationOutcome.ignored.rawValue)
        }
        try? context.save()
    }

    // MARK: - Private scheduling helpers

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    private static func staleManagedIds(
        from requests: [UNNotificationRequest],
        keepDayStamps: Set<String>
    ) -> [String] {
        let calendar = Calendar.current
        var stale: [String] = []
        for request in requests {
            guard let parts = parseIdentifier(request.identifier) else {
                stale.append(request.identifier)
                continue
            }
            if !keepDayStamps.contains(parts.dayStamp) || parts.index < 1 || parts.index > pingsPerDay {
                stale.append(request.identifier)
                continue
            }
            guard
                let fireDate   = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                let dayStart   = dateFromDayStamp(parts.dayStamp),
                let windowStart = calendar.date(bySettingHour: windowStartHour, minute: 0, second: 0, of: dayStart),
                let tomorrow   = calendar.date(byAdding: .day, value: 1, to: dayStart),
                let windowEnd  = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: tomorrow)
            else {
                stale.append(request.identifier)
                continue
            }
            if fireDate < windowStart || fireDate >= windowEnd {
                stale.append(request.identifier)
            }
        }
        return stale
    }

    private static func dayStamp(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func pingIdentifier(dayStamp: String, index: Int) -> String {
        "\(idPrefix)\(dayStamp)_\(index)"
    }

    private static func parseIdentifier(_ id: String) -> (dayStamp: String, index: Int)? {
        guard id.hasPrefix(idPrefix) else { return nil }
        let suffix = String(id.dropFirst(idPrefix.count))
        let parts  = suffix.split(separator: "_")
        guard parts.count == 2, let index = Int(parts[1]) else { return nil }
        return (String(parts[0]), index)
    }

    private static func dateFromDayStamp(_ stamp: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale   = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: stamp)
    }

    private static func managedRequestsByDayAndIndex(
        from requests: [UNNotificationRequest]
    ) -> [String: [Int: UNNotificationRequest]] {
        var result: [String: [Int: UNNotificationRequest]] = [:]
        for request in requests {
            guard let parsed = parseIdentifier(request.identifier) else { continue }
            var dayMap = result[parsed.dayStamp] ?? [:]
            dayMap[parsed.index] = request
            result[parsed.dayStamp] = dayMap
        }
        return result
    }

    private static func scheduleMissingPings(
        forDayStart dayStart: Date,
        now: Date,
        existingByIndex: [Int: UNNotificationRequest]
    ) {
        let dayStampValue   = dayStamp(for: dayStart)
        let missingIndices  = (1...pingsPerDay).filter { existingByIndex[$0] == nil }
        guard !missingIndices.isEmpty else { return }

        let existingDates   = existingByIndex.values.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }
        let generatedDates  = generateTimes(
            forDayStart: dayStart,
            now: now,
            existingDates: existingDates,
            neededCount: missingIndices.count
        )
        guard !generatedDates.isEmpty else { return }

        for (index, date) in zip(missingIndices.sorted(), generatedDates.sorted()) {
            schedulePing(at: date, notificationId: pingIdentifier(dayStamp: dayStampValue, index: index))
        }
    }

    private static func generateTimes(
        forDayStart dayStart: Date,
        now: Date,
        existingDates: [Date],
        neededCount: Int
    ) -> [Date] {
        let calendar = Calendar.current
        guard
            let windowStart = calendar.date(bySettingHour: windowStartHour, minute: 0, second: 0, of: dayStart),
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart),
            let windowEnd = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: tomorrowStart)
        else { return [] }

        let notNowEpoch = defaults.double(forKey: notNowUntilKey)
        let notNowUntil = Date(timeIntervalSince1970: notNowEpoch)
        let isToday     = calendar.isDate(dayStart, inSameDayAs: now)

        var lowerBound = windowStart
        if isToday          { lowerBound = max(lowerBound, now.addingTimeInterval(5)) }
        if notNowEpoch > 0  { lowerBound = max(lowerBound, notNowUntil) }

        let lower = lowerBound.timeIntervalSince1970
        let upper = windowEnd.timeIntervalSince1970
        guard upper > lower else { return [] }

        var chosen = existingDates
        let existingCount = existingDates.count
        var attempts = 0
        while (chosen.count - existingCount) < neededCount && attempts < 500 {
            attempts += 1
            let candidate = Date(timeIntervalSince1970: Double.random(in: lower...upper))
            if chosen.allSatisfy({ abs($0.timeIntervalSince(candidate)) >= minGapSeconds }) {
                chosen.append(candidate)
            }
        }
        return Array(chosen.dropFirst(existingCount)).sorted()
    }

    private static func schedulePing(at date: Date, notificationId: String) {
        let content = UNMutableNotificationContent()
        content.title              = "Quick check-in"
        content.body               = "Are you interruptible right now?"
        content.sound              = .default
        content.categoryIdentifier = categoryId
        // notificationId is the single canonical source for both the request identifier
        // and the userInfo lookup keys — they are always derived from the same constant.
        content.userInfo = [
            "notificationId": notificationId,
            "kind":           "interruptibility_ping",
            "isTest":         false
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let trigger  = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request  = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        let scheduledISO = ISO8601DateHelper.encodeISO(date)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[PingDebug] schedule failed id=\(notificationId) error=\(error.localizedDescription)")
                return
            }
            let modeRaw = UserDefaults(suiteName: appGroupId)?.string(forKey: "experimentMode")
                ?? UserDefaults.standard.string(forKey: "experimentMode")
                ?? ExperimentMode.baseline.rawValue

            // Write pending metadata only — no TelemetryEvent at schedule time.
            // Delivery timestamp and outcome are recorded later via willPresent / didReceive.
            let entry = PendingPingEntry(
                requestIdentifier: notificationId,
                scheduledForISO: scheduledISO,
                modeRaw: modeRaw
            )
            savePendingEntry(entry)
            print("[PingDebug] ping_pending id=\(notificationId) scheduledFor=\(scheduledISO)")
        }
    }
}
