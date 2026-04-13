//
//  HomeView.swift
//  Project Apple
//
//  Created by Farzaan Dalwai on 2/5/26.
//

import SwiftUI

struct HomeView: View {
    @AppStorage("experimentMode") private var experimentModeRaw: String = ExperimentMode.baseline.rawValue

    private var experimentMode: ExperimentMode {
        ExperimentMode(rawValue: experimentModeRaw) ?? .baseline
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Home")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Mode: \(experimentMode.displayName)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Your personalized home feed is coming soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
