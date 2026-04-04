//
//  ContentView.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MetricsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Context Meter")
                .font(.headline)
            Text(statusText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 360, minHeight: 260)
        .onAppear { viewModel.refresh() }
    }

    private var statusText: String {
        var lines: [String] = []

        if let c = viewModel.context {
            lines += [
                "── Context Window ──────────────",
                "File:  \(c.fileName)",
                "Model: \(c.model)",
                "Fill:  \(c.fillPercent)%  (\(c.totalTokens) / \(c.contextLimit))",
                "       in \(c.inputTokens)  cache \(c.cacheReadTokens)  out \(c.outputTokens)",
            ]
        } else {
            lines.append("Context window: no data")
        }

        lines.append("")

        let b = viewModel.billing
        lines += [
            "── Billing Window (5 hr) ───────",
            "Output tokens: \(b?.outputTokens ?? 0) / \(b?.tokenLimit ?? 0)",
            "Fill:  \(b?.fillPercent ?? 0)%",
            "Resets in: \(b?.timeUntilReset ?? "--")",
        ]

        return lines.joined(separator: "\n")
    }
}

#Preview {
    ContentView()
        .environmentObject(MetricsViewModel())
}
