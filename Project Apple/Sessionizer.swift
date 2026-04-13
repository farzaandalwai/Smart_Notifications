//
//  Sessionizer.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import Foundation
import SwiftData

struct Sessionizer {
    
    // MARK: - Main sessionization
    
    static func sessionize(context: ModelContext) {
        let events = fetchRelevantEvents(context: context)
        guard !events.isEmpty else { return }
        
        let existingSessionIds = fetchExistingSessionIds(context: context)
        var newSessions: [AppSession] = []
        
        // Group events by app and process pairs
        var i = 0
        while i < events.count {
            let event = events[i]
            
            // Only process app_opened events
            guard event.eventType == "app_opened" else {
                i += 1
                continue
            }
            
            let appName = extractAppName(from: event)
            let openTime = event.timestamp
            let mode = event.mode
            
            // Find matching close
            var closeIdx: Int? = nil
            for j in (i + 1)..<events.count {
                let candidate = events[j]
                let candidateApp = extractAppName(from: candidate)
                
                if candidateApp == appName && candidate.eventType == "app_closed" {
                    closeIdx = j
                    break
                }
            }
            
            guard let closeIdx = closeIdx else {
                i += 1
                continue
            }
            
            let closeEvent = events[closeIdx]
            let closeTime = closeEvent.timestamp
            let duration = closeTime.timeIntervalSince(openTime)
            
            // Validate duration
            guard duration >= 0 && duration <= 12 * 3600 else {
                i += 1
                continue
            }
            
            // Generate session key
            let sessionKey = generateSessionKey(appName: appName, start: openTime, end: closeTime)
            
            // Skip if already exists
            guard !existingSessionIds.contains(sessionKey) else {
                i = closeIdx + 1
                continue
            }
            
            // Derive prev/next app
            let prevApp = extractPrevApp(events: events, beforeIndex: i)
            let nextApp = extractNextApp(events: events, afterIndex: closeIdx)
            
            // Determine switch type
            let switchType = determineSwitchType(events: events, afterCloseIndex: closeIdx)
            
            let session = AppSession(
                sessionId: sessionKey,
                appName: appName,
                startTime: openTime,
                endTime: closeTime,
                durationSec: duration,
                modeRaw: mode,
                prevApp: prevApp,
                nextApp: nextApp,
                switchType: switchType
            )
            
            newSessions.append(session)
            i = closeIdx + 1
        }
        
        // Insert new sessions
        for session in newSessions {
            context.insert(session)
        }
        
        try? context.save()
    }
    
    // MARK: - Rebuild (delete all + recreate)
    
    static func rebuildSessions(context: ModelContext) {
        // Delete all existing sessions
        let descriptor = FetchDescriptor<AppSession>()
        if let existing = try? context.fetch(descriptor) {
            for session in existing {
                context.delete(session)
            }
        }
        
        try? context.save()
        
        // Rebuild from scratch
        sessionize(context: context)
    }
    
    // MARK: - Helpers
    
    private static func fetchRelevantEvents(context: ModelContext) -> [TelemetryEvent] {
        let descriptor = FetchDescriptor<TelemetryEvent>(
            predicate: #Predicate { event in
                event.eventType == "app_opened" || event.eventType == "app_closed"
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    private static func fetchExistingSessionIds(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<AppSession>()
        guard let sessions = try? context.fetch(descriptor) else {
            return []
        }
        return Set(sessions.map(\.sessionId))
    }
    
    private static func extractAppName(from event: TelemetryEvent) -> String {
        // Try metadata first (for buffered shortcut events)
        if let metadata = try? JSONSerialization.jsonObject(with: Data(event.metadataJson.utf8)) as? [String: String],
           let sourceApp = metadata["sourceApp"] {
            return sourceApp
        }
        
        // Fallback to module
        return event.module
    }
    
    private static func extractPrevApp(events: [TelemetryEvent], beforeIndex: Int) -> String? {
        // Look backward for the most recent app_closed
        for i in stride(from: beforeIndex - 1, through: 0, by: -1) {
            let event = events[i]
            if event.eventType == "app_closed" {
                return extractAppName(from: event)
            }
        }
        return nil
    }
    
    private static func extractNextApp(events: [TelemetryEvent], afterIndex: Int) -> String? {
        // Look forward for the next app_opened
        for i in (afterIndex + 1)..<events.count {
            let event = events[i]
            if event.eventType == "app_opened" {
                return extractAppName(from: event)
            }
        }
        return nil
    }
    
    private static func determineSwitchType(events: [TelemetryEvent], afterCloseIndex: Int) -> String {
        guard afterCloseIndex + 1 < events.count else {
            return "normal"
        }
        
        let closeEvent = events[afterCloseIndex]
        let nextEvent = events[afterCloseIndex + 1]
        
        if nextEvent.eventType == "app_opened" {
            let gap = nextEvent.timestamp.timeIntervalSince(closeEvent.timestamp)
            return gap <= 15.0 ? "rapid" : "normal"
        }
        
        return "normal"
    }
    
    private static func generateSessionKey(appName: String, start: Date, end: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startISO = formatter.string(from: start)
        let endISO = formatter.string(from: end)
        return "\(appName)|\(startISO)|\(endISO)"
    }
}
