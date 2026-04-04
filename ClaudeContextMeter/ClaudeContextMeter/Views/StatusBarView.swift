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
        case 85...: return "🔴"
        case 60...: return "🟡"
        default:    return "🟢"
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        StatusBarView(contextFill: 17, billingFill: 33)   // both green
        StatusBarView(contextFill: 70, billingFill: 33)   // yellow + green
        StatusBarView(contextFill: 90, billingFill: 88)   // both red
    }
    .padding()
}
