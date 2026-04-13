//
//  InterruptibilityDebugCard.swift
//  Project Apple
//
//  Debug card for verifying the interruptibility model output on-device.
//  Wire this up wherever you want to test; currently shown in AnalyticsView
//  under #if DEBUG. Remove or keep it gated when you ship.
//
//  To add elsewhere:
//      InterruptibilityDebugCard()
//

import SwiftUI

struct InterruptibilityDebugCard: View {
    @State private var result: InterruptibilityResult? = nil
    @State private var errorMessage: String? = nil
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interruptibility Model")
                    .font(.headline)
                Spacer()
                Text("DEBUG")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }

            if let result {
                ResultView(result: result)
            } else if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else {
                Text("Tap below to run a sample prediction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: runSamplePrediction) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(result == nil ? "Run Sample Prediction" : "Refresh")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .onAppear { runSamplePrediction() }
    }

    private func runSamplePrediction() {
        isRunning = true
        errorMessage = nil
        // Off main thread so Core ML doesn't block UI.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let features = InterruptibilityRawFeatures.sample()
                let prediction = try InterruptibilityEngine.predict(features)
                DispatchQueue.main.async {
                    result = prediction
                    isRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }
}

// MARK: - Result sub-view

private struct ResultView: View {
    let result: InterruptibilityResult

    private var probabilityPercent: String {
        String(format: "%.0f%%", result.probabilityUsefulNow * 100)
    }

    private var actionColor: Color {
        switch result.action {
        case .sendNow:    return .green
        case .delay15Min: return .orange
        case .digest:     return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Probability circle
            ZStack {
                Circle()
                    .stroke(actionColor.opacity(0.25), lineWidth: 4)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: result.probabilityUsefulNow)
                    .stroke(actionColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                Text(probabilityPercent)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(actionColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(result.action.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(actionColor)
                Text(result.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Send Now") {
    InterruptibilityDebugCard()
        .padding()
}

#Preview("With canned result") {
    let r = InterruptibilityResult(
        probabilityUsefulNow: 0.78,
        action: .sendNow,
        explanation: "Recent activity is high"
    )
    return ResultView(result: r)
        .padding()
}
