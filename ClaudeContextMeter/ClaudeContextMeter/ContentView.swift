//
//  ContentView.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

struct ContentView: View {
    @State private var statusText = "Reading..."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Context Meter")
                .font(.headline)
            Text(statusText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 200)
        .onAppear { loadData() }
    }

    private func loadData() {
        guard let metrics = ContextWindowCalculator.calculate() else {
            statusText = "No session data found."
            return
        }

        statusText = """
        File: \(metrics.fileName)
        Model: \(metrics.model)
        Tokens used: \(metrics.totalTokens) / \(metrics.contextLimit)
        Context fill: \(metrics.fillPercent)%
        (input: \(metrics.inputTokens), cache: \(metrics.cacheReadTokens), output: \(metrics.outputTokens))
        """
    }
}

#Preview {
    ContentView()
}
