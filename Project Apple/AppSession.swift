//
//  AppSession.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import Foundation
import SwiftData

@Model
class AppSession {
    @Attribute(.unique) var sessionId: String
    var appName: String
    var startTime: Date
    var endTime: Date
    var durationSec: Double
    var modeRaw: String
    var prevApp: String?
    var nextApp: String?
    var switchType: String
    var source: String
    
    init(
        sessionId: String,
        appName: String,
        startTime: Date,
        endTime: Date,
        durationSec: Double,
        modeRaw: String,
        prevApp: String? = nil,
        nextApp: String? = nil,
        switchType: String,
        source: String = "sessionizer_v1"
    ) {
        self.sessionId = sessionId
        self.appName = appName
        self.startTime = startTime
        self.endTime = endTime
        self.durationSec = durationSec
        self.modeRaw = modeRaw
        self.prevApp = prevApp
        self.nextApp = nextApp
        self.switchType = switchType
        self.source = source
    }
}
