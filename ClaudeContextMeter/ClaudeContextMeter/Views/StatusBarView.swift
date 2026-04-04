//
//  StatusBarView.swift
//  ClaudeContextMeter
//

import SwiftUI

struct StatusBarView: View {
    let contextFill: Int
    let billingFill: Int

    var body: some View {
        Text("\(dotEmoji(for: contextFill))\(dotEmoji(for: billingFill))")
            .font(.system(size: 12))
    }

    private func dotEmoji(for percent: Int) -> String {
        switch percent {
        case 70...: return "🔴"  // compaction imminent (~80% trigger is 10% away)
        case 50...: return "🟠"  // voluntary compact zone, cost climbing fast
        case 33...: return "🟡"  // awareness zone, rising cost
        default:    return "🟢"  // lean and efficient
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        StatusBarView(contextFill: 20, billingFill: 20)   // 🟢🟢 lean
        StatusBarView(contextFill: 40, billingFill: 40)   // 🟡🟡 awareness
        StatusBarView(contextFill: 60, billingFill: 60)   // 🟠🟠 compact now
        StatusBarView(contextFill: 75, billingFill: 75)   // 🔴🔴 compaction imminent
    }
    .padding()
}
