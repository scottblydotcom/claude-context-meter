//
//  WeeklyUsageCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum WeeklyUsageCalculator {

    static let weekdayKey = "weeklyResetWeekday"  // Calendar weekday: 1=Sun … 7=Sat
    static let hourKey    = "weeklyResetHour"      // 0–23

    /// Default: Tuesday (Calendar weekday 3) at 9 PM — matches Anthropic Pro plan.
    static let defaultWeekday = 3
    static let defaultHour    = 21

    static var resetWeekday: Int {
        UserDefaults.standard.object(forKey: weekdayKey) != nil
            ? UserDefaults.standard.integer(forKey: weekdayKey)
            : defaultWeekday
    }

    static var resetHour: Int {
        UserDefaults.standard.object(forKey: hourKey) != nil
            ? UserDefaults.standard.integer(forKey: hourKey)
            : defaultHour
    }

    /// Returns the start of the current weekly window — the most recent occurrence
    /// of [resetWeekday] at [resetHour]:00:00 that is on or before `now`.
    static func findWeeklyWindowStart(relativeTo now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let targetWeekday = resetWeekday
        let targetHour    = resetHour

        // Walk backward day by day (max 8 = full week + 1 safety) until we land
        // on the right weekday with the reset hour already past.
        var candidate = now
        for _ in 0...7 {
            var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
            comps.hour   = targetHour
            comps.minute = 0
            comps.second = 0
            let resetOnThisDay = calendar.date(from: comps)!

            if calendar.component(.weekday, from: candidate) == targetWeekday,
               resetOnThisDay <= now {
                return resetOnThisDay
            }
            candidate = calendar.date(byAdding: .day, value: -1, to: candidate)!
        }

        // Fallback: 7 days ago (should never be reached)
        return calendar.date(byAdding: .day, value: -7, to: now)!
    }

    /// Returns true if `date` falls within Anthropic's peak-usage hours:
    /// Monday–Friday, 5 AM–10:59 AM Pacific Time.
    ///
    /// During peak hours Anthropic counts tokens ~2× faster against the weekly limit.
    static func isPeakHour(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let comps = cal.dateComponents([.weekday, .hour], from: date)
        guard let weekday = comps.weekday, let hour = comps.hour else { return false }
        // weekday: 1=Sun, 2=Mon … 6=Fri, 7=Sat
        return (2...6).contains(weekday) && (5..<11).contains(hour)
    }

    /// Scans all JSONL files and sums tokens since the start of the current weekly window,
    /// returning counts for all three candidate counting methods plus a peak-adjusted total.
    static func calculate() -> WeeklyUsageMetrics {
        let now         = Date()
        let windowStart = findWeeklyWindowStart(relativeTo: now)
        let nextReset   = Calendar.current.date(byAdding: .day, value: 7, to: windowStart)!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Deduplicate by requestId; keep only complete records within the window.
        struct Tally { var input, cacheCreate, cacheRead, output: Int; var isPeak: Bool }
        var byRequest: [String: Tally] = [:]

        for url in JSONLParser.allSessionFiles() {
            guard let records = try? JSONLParser.parse(fileURL: url) else { continue }
            for record in records {
                guard record.isCompleteAssistantRecord,
                      let rid     = record.requestId,
                      let ts      = formatter.date(from: record.timestamp),
                      ts >= windowStart, ts <= now,
                      let usage   = record.message?.usage
                else { continue }

                byRequest[rid] = Tally(
                    input:       usage.inputTokens,
                    cacheCreate: usage.cacheCreationInputTokens ?? 0,
                    cacheRead:   usage.cacheReadInputTokens     ?? 0,
                    output:      usage.outputTokens,
                    isPeak:      isPeakHour(ts)
                )
            }
        }

        var totalInput = 0, totalCC = 0, totalCR = 0, totalOutput = 0
        var peakInput  = 0, peakCC  = 0, peakCR  = 0, peakOutput  = 0
        for t in byRequest.values {
            totalInput  += t.input;       totalCC += t.cacheCreate
            totalCR     += t.cacheRead;   totalOutput += t.output
            let m = t.isPeak ? 2 : 1
            peakInput  += t.input * m;    peakCC += t.cacheCreate * m
            peakCR     += t.cacheRead * m; peakOutput += t.output * m
        }

        return WeeklyUsageMetrics(
            allTokens:           totalInput + totalCC + totalCR + totalOutput,
            noCacheRead:         totalInput + totalCC + totalOutput,
            inputOutputOnly:     totalInput + totalOutput,
            peakAdjustedTokens:  peakInput  + peakCC  + peakCR  + peakOutput,
            windowStart:         windowStart,
            nextReset:           nextReset
        )
    }
}
