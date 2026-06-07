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

    private struct Tally {
        var input, cacheCreate, cacheRead, output: Int64
    }

    /// Core calculation: accepts a pre-built file list.
    static func calculate(files: [URL]) -> WeeklyUsageMetrics {
        let now         = Date()
        let windowStart = findWeeklyWindowStart(relativeTo: now)
        let nextReset   = Calendar.current.date(byAdding: .day, value: 7, to: windowStart)!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var byRequest: [String: Tally] = [:]

        for url in files {
            guard let records = try? JSONLParser.parse(fileURL: url) else { continue }
            for record in records {
                guard record.isCompleteAssistantRecord,
                      let rid = record.requestId,
                      let timestamp = formatter.date(from: record.timestamp),
                      timestamp >= windowStart, timestamp <= now,
                      let usage = record.message?.usage
                else { continue }

                byRequest[rid] = Tally(
                    input: usage.inputTokens,
                    cacheCreate: usage.cacheCreationInputTokens ?? 0,
                    cacheRead: usage.cacheReadInputTokens ?? 0,
                    output: usage.outputTokens
                )
            }
        }

        let totals = accumulateTotals(byRequest.values)
        return WeeklyUsageMetrics(
            allTokens: totals.input + totals.cacheCreate + totals.cacheRead + totals.output,
            noCacheRead: totals.input + totals.cacheCreate + totals.output,
            inputOutputOnly: totals.input + totals.output,
            windowStart: windowStart,
            nextReset: nextReset
        )
    }

    /// Convenience wrapper: scans files since the current weekly window start.
    static func calculate() -> WeeklyUsageMetrics {
        let windowStart = findWeeklyWindowStart()
        let files = JSONLParser.allSessionFiles(modifiedSince: windowStart)
        return calculate(files: files)
    }

    private struct Totals {
        var input, cacheCreate, cacheRead, output: Int64
    }

    private static func accumulateTotals(_ tallies: some Collection<Tally>) -> Totals {
        var acc = Totals(input: 0, cacheCreate: 0, cacheRead: 0, output: 0)
        for tally in tallies {
            acc.input += tally.input
            acc.cacheCreate += tally.cacheCreate
            acc.cacheRead += tally.cacheRead
            acc.output += tally.output
        }
        return acc
    }
}
