//
//  BillingWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum BillingWindowCalculator {

    static let limitKey      = "billingTokenLimit"
    static let windowDuration: TimeInterval = 5 * 3600  // 5 hours

    /// Default output token limit (user-configurable to match their Claude plan).
    static let defaultLimit: Int64 = 131_000

    /// The current billing token limit, falls back to default.
    static var tokenLimit: Int64 {
        let stored = UserDefaults.standard.integer(forKey: limitKey)
        return stored > 0 ? Int64(stored) : defaultLimit
    }

    /// Given a sorted array of record timestamps, returns the start of the current
    /// rolling 5-hour window, or nil if no active window exists.
    ///
    /// A new window begins after any gap >= windowDuration between consecutive records.
    /// Returns nil if the array is empty or the most recent window has already expired.
    static func findWindowStart(from sortedTimestamps: [Date], relativeTo now: Date = Date()) -> Date? {
        guard !sortedTimestamps.isEmpty else { return nil }

        // Walk forward: each gap >= 5h starts a new window.
        var windowStartIndex = 0
        for idx in 1..<sortedTimestamps.count {
            let gap = sortedTimestamps[idx].timeIntervalSince(sortedTimestamps[idx - 1])
            if gap >= windowDuration {
                windowStartIndex = idx
            }
        }

        let rawStart = sortedTimestamps[windowStartIndex]
        // Anthropic anchors the billing window to the top of the hour of the first request.
        var windowStart = Calendar.current.dateInterval(of: .hour, for: rawStart)?.start ?? rawStart

        // Cycle forward through expired windows. When a window expires, Anthropic starts
        // the next window anchored to the top of the hour of the FIRST request after the
        // reset — not simply windowStart + windowDuration. Using nextReset as the new
        // anchor is wrong when the user paused after the reset (e.g., window expired at
        // 11:00 AM, next request at 12:23 PM → new window is 12:00 PM–5:00 PM, not
        // 11:00 AM–4:00 PM).
        while true {
            let nextReset = windowStart.addingTimeInterval(windowDuration)
            if nextReset > now {
                return windowStart
            }
            // This window has expired. Find the first record that opened the next window
            // and re-anchor to the top of THAT hour.
            guard let firstInNextWindow = sortedTimestamps.first(where: { $0 >= nextReset }) else {
                return nil
            }
            windowStart = Calendar.current.dateInterval(of: .hour, for: firstInNextWindow)?.start ?? firstInNextWindow
        }
    }

    /// Scans JSONL files, derives the rolling window start from record timestamps,
    /// and sums output tokens in the current window.
    static func calculate() -> BillingWindowMetrics {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Look back 10h: enough to find window boundaries (window is 5h, so
        // a boundary record could sit just outside the 5h mark).
        let lookback = now.addingTimeInterval(-10 * 3600)

        // earliestTimestamp: tracks the earliest timestamp seen for each requestId
        // across ALL assistant records (including streaming partials). Streaming
        // partials are timestamped at request start, before the response finishes,
        // so they give us a more accurate window-start anchor than complete records.
        var earliestTimestamp: [String: Date] = [:]
        var outputTokensByRequestId: [String: Int64] = [:]

        for url in JSONLParser.allSessionFiles() {
            guard let parsed = try? JSONLParser.parse(fileURL: url) else { continue }
            for record in parsed {
                guard record.type == "assistant" || record.type == "user",
                      let rid = record.requestId,
                      let timestamp = formatter.date(from: record.timestamp),
                      timestamp >= lookback
                else { continue }

                // Keep the earliest timestamp for this requestId.
                if let existing = earliestTimestamp[rid] {
                    if timestamp < existing { earliestTimestamp[rid] = timestamp }
                } else {
                    earliestTimestamp[rid] = timestamp
                }

                // Collect output tokens from complete records only.
                if record.isCompleteAssistantRecord,
                   let outputTokens = record.message?.usage?.outputTokens {
                    outputTokensByRequestId[rid] = outputTokens
                }
            }
        }

        // Build records using earliest timestamps, only for requestIds with output tokens.
        var records: [(timestamp: Date, outputTokens: Int64)] = []
        for (rid, outputTokens) in outputTokensByRequestId {
            guard let timestamp = earliestTimestamp[rid] else { continue }
            records.append((timestamp: timestamp, outputTokens: outputTokens))
        }
        records.sort { $0.timestamp < $1.timestamp }

        let timestamps = records.map { $0.timestamp }
        guard let windowStart = findWindowStart(from: timestamps, relativeTo: now) else {
            // No active window detected — no recent JSONL data.
            return BillingWindowMetrics(outputTokens: 0, tokenLimit: tokenLimit,
                                        windowStart: now, nextReset: now.addingTimeInterval(windowDuration))
        }

        let nextReset = windowStart.addingTimeInterval(windowDuration)
        let totalOutputTokens: Int64 = records
            .filter { $0.timestamp >= windowStart }
            .reduce(0) { $0 + $1.outputTokens }

        return BillingWindowMetrics(
            outputTokens: totalOutputTokens,
            tokenLimit: tokenLimit,
            windowStart: windowStart,
            nextReset: nextReset
        )
    }
}
