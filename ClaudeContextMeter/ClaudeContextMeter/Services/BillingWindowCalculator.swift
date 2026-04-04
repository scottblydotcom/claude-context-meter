//
//  BillingWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum BillingWindowCalculator {

    static let limitKey   = "billingTokenLimit"
    static let anchorKey  = "billingWindowAnchor"
    static let windowDuration: TimeInterval = 5 * 3600  // 5 hours

    /// Default output token limit (user-configurable to match their Claude plan).
    static let defaultLimit = 131_000

    /// The current billing token limit, falls back to default.
    static var tokenLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: limitKey)
        return stored > 0 ? stored : defaultLimit
    }

    /// The anchor timestamp: the top-of-hour when the schedule was first established.
    /// Defaults to the most recent top-of-hour on first launch.
    static var windowAnchor: Date {
        get {
            let stored = UserDefaults.standard.double(forKey: anchorKey)
            if stored > 0 { return Date(timeIntervalSince1970: stored) }
            // Default: most recent top-of-hour in local time
            let cal = Calendar.current
            let components = cal.dateComponents([.year, .month, .day, .hour], from: Date())
            let anchor = cal.date(from: components) ?? Date()
            UserDefaults.standard.set(anchor.timeIntervalSince1970, forKey: anchorKey)
            return anchor
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: anchorKey)
        }
    }

    /// Start of the current 5-hour window, computed from the anchor.
    static func currentWindowStart() -> Date {
        let anchor = windowAnchor
        let elapsed = Date().timeIntervalSince(anchor)
        let periods = floor(elapsed / windowDuration)
        return anchor.addingTimeInterval(periods * windowDuration)
    }

    /// Sums output tokens within the current 5-hour window, deduplicated by requestId.
    static func calculate() -> BillingWindowMetrics {
        let windowStart = currentWindowStart()
        let nextReset   = windowStart.addingTimeInterval(windowDuration)
        let formatter   = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var seen = Set<String>()
        var totalOutputTokens = 0

        for url in JSONLParser.allSessionFiles() {
            guard let records = try? JSONLParser.parse(fileURL: url) else { continue }
            for record in records {
                guard record.isCompleteAssistantRecord,
                      let rid = record.requestId,
                      seen.insert(rid).inserted,
                      let timestamp = formatter.date(from: record.timestamp),
                      timestamp >= windowStart,
                      let outputTokens = record.message?.usage?.outputTokens
                else { continue }
                totalOutputTokens += outputTokens
            }
        }

        return BillingWindowMetrics(
            outputTokens: totalOutputTokens,
            tokenLimit: tokenLimit,
            windowStart: windowStart,
            nextReset: nextReset
        )
    }
}
