//
//  LiveView.swift
//  Project Apple
//

import SwiftUI

struct LiveView: View {
    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue

    private var experimentMode: ExperimentMode {
        ExperimentMode(rawValue: experimentModeRaw) ?? .baseline
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Live")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Mode: \(experimentMode.displayName)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Live activity tracking will appear here soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    LiveView()
}
