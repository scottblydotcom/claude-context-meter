//
//  UsageMetrics.swift
//  ClaudeContextMeter
//

import Foundation

/// The calculated context window metrics for the most recent Claude session turn.
struct ContextWindowMetrics {
    let fileName: String
    let model: String
    let totalTokens: Int
    let contextLimit: Int
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int

    /// Percentage of context window filled (0–100).
    var fillPercent: Int {
        guard contextLimit > 0 else { return 0 }
        return Int((Double(totalTokens) / Double(contextLimit)) * 100)
    }
}

/// The calculated billing window metrics for the current 5-hour window.
struct BillingWindowMetrics {
    let outputTokens: Int
    let tokenLimit: Int
    let windowStart: Date
    let nextReset: Date

    /// Percentage of billing token limit used (0–100).
    var fillPercent: Int {
        guard tokenLimit > 0 else { return 0 }
        return Int((Double(outputTokens) / Double(tokenLimit)) * 100)
    }

    /// Human-readable time until next window reset, e.g. "4h 18m".
    var timeUntilReset: String {
        let seconds = max(0, nextReset.timeIntervalSinceNow)
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Absolute clock time the current window started, e.g. "10:23 AM".
    var windowStartTime: String { Self.shortTime(windowStart) }

    /// Absolute clock time of the next reset, e.g. "3:23 PM".
    var nextResetTime: String { Self.shortTime(nextReset) }

    private static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
