//
//  NetworkStateMonitor.swift
//  Project Apple
//

import Foundation
import Network

final class NetworkStateMonitor {
    static let shared = NetworkStateMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "projectapple.network.monitor")
    private var isStarted = false
    private var appGroupId = "group.com.farzaan.projectapple"

    private init() {}

    func start(appGroupId: String) {
        guard !isStarted else { return }
        self.appGroupId = appGroupId
        isStarted = true

        monitor.pathUpdateHandler = { path in
            let latestNetwork: String
            if path.status != .satisfied {
                latestNetwork = "offline"
            } else if path.usesInterfaceType(.wifi) {
                latestNetwork = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                latestNetwork = "cellular"
            } else {
                latestNetwork = "unknown"
            }

            let defaults = UserDefaults(suiteName: appGroupId)
            defaults?.set(latestNetwork, forKey: "latestNetwork")
        }

        monitor.start(queue: queue)
    }
}
