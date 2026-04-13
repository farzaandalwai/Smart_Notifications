//
//  VoiceView.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import SwiftUI

struct VoiceView: View {
    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue

    private var experimentMode: ExperimentMode {
        ExperimentMode(rawValue: experimentModeRaw) ?? .baseline
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Voice")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Mode: \(experimentMode.displayName)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Voice insights and controls are coming soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    VoiceView()
}
