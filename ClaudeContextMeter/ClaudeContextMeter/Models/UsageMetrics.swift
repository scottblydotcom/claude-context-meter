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

/// The calculated weekly usage metrics across all three token-counting methods.
struct WeeklyUsageMetrics {
    /// input + cache_create + cache_read + output
    let allTokens: Int
    /// input + cache_create + output (excludes cache reads)
    let noCacheRead: Int
    /// input + output only
    let inputOutputOnly: Int
    /// allTokens with 2× multiplier applied to tokens from peak-hour requests
    /// (Mon–Fri 5–11 AM PT), matching Anthropic's peak-usage billing behavior.
    let peakAdjustedTokens: Int
    let windowStart: Date
    let nextReset: Date

    /// Human-readable time until next weekly reset, e.g. "3d 2h" or "4h 13m".
    var timeUntilReset: String {
        let secs = max(0, nextReset.timeIntervalSinceNow)
        let days = Int(secs) / 86400
        let hours = (Int(secs) % 86400) / 3600
        let minutes = (Int(secs) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Formatted next reset label matching Claude's UI, e.g. "Tue 9:00 PM".
    var nextResetDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: nextReset)
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
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Absolute clock time the current window started, e.g. "10:23 AM".
    var windowStartTime: String { Self.shortTime(windowStart) }

    /// Absolute clock time of the next reset, e.g. "3:23 PM".
    var nextResetTime: String { Self.shortTime(nextReset) }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
