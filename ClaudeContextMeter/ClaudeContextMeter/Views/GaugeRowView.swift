//
//  GaugeRowView.swift
//  ClaudeContextMeter
//

import SwiftUI

/// A labeled progress bar showing a fill percentage with threshold-aware color.
struct GaugeRowView: View {
    let label: String
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(fillColor(for: percent))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fillColor(for: percent))
                        .frame(width: geo.size.width * min(CGFloat(percent) / 100, 1.0))
                }
            }
            .frame(height: 5)
        }
    }
}

/// Threshold-aware fill color matching the menu bar dot thresholds.
func fillColor(for percent: Int) -> Color {
    switch percent {
    case 70...: return .red
    case 50...: return .orange
    case 33...: return .yellow
    default:    return .green
    }
}

#Preview {
    VStack(spacing: 16) {
        GaugeRowView(label: "Context Window", percent: 20)
        GaugeRowView(label: "Context Window", percent: 40)
        GaugeRowView(label: "Context Window", percent: 60)
        GaugeRowView(label: "Context Window", percent: 75)
    }
    .padding()
    .frame(width: 300)
}
