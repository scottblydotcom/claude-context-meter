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

    /// Pricing per million tokens (USD). Cache creation = 1.25x input rate; cache read = 0.1x input rate.
    /// Defaults to Sonnet rates for unknown models.
    private static func tokenCost(
        model: String, input: Int64, cacheCreate: Int64, cacheRead: Int64, output: Int64
    ) -> Double {
        let inputRate: Double
        let outputRate: Double
        if model.contains("opus") {
            inputRate = 15.00; outputRate = 75.00
        } else if model.contains("haiku") {
            inputRate = 0.80; outputRate = 4.00
        } else {
            inputRate = 3.00; outputRate = 15.00
        }
        let ccRate = inputRate * 1.25
        let crRate = inputRate * 0.1
        let perM = 1_000_000.0
        return Double(input)       / perM * inputRate
             + Double(cacheCreate) / perM * ccRate
             + Double(cacheRead)   / perM * crRate
             + Double(output)      / perM * outputRate
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

    private struct Tally {
        var input, cacheCreate, cacheRead, output: Int64
        var isPeak: Bool
        var model: String
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
        var byRequest: [String: Tally] = [:]

        for url in JSONLParser.allSessionFiles(modifiedSince: windowStart) {
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
                    output: usage.outputTokens,
                    isPeak: isPeakHour(timestamp),
                    model: record.message?.model ?? ""
                )
            }
        }

        let totals = accumulateTotals(byRequest.values)
        return WeeklyUsageMetrics(
            allTokens: totals.input + totals.cacheCreate + totals.cacheRead + totals.output,
            noCacheRead: totals.input + totals.cacheCreate + totals.output,
            inputOutputOnly: totals.input + totals.output,
            peakAdjustedTokens: totals.peakInput + totals.peakCC + totals.peakCR + totals.peakOutput,
            costWeighted: totals.cost,
            windowStart: windowStart,
            nextReset: nextReset
        )
    }

    private struct Totals {
        var input, cacheCreate, cacheRead, output: Int64
        var peakInput, peakCC, peakCR, peakOutput: Int64
        var cost: Double
    }

    private static func accumulateTotals(_ tallies: some Collection<Tally>) -> Totals {
        var acc = Totals(input: 0, cacheCreate: 0, cacheRead: 0, output: 0,
                         peakInput: 0, peakCC: 0, peakCR: 0, peakOutput: 0, cost: 0)
        for tally in tallies {
            acc.input += tally.input; acc.cacheCreate += tally.cacheCreate
            acc.cacheRead += tally.cacheRead; acc.output += tally.output
            let multiplier: Int64 = tally.isPeak ? 2 : 1
            acc.peakInput += tally.input * multiplier; acc.peakCC += tally.cacheCreate * multiplier
            acc.peakCR += tally.cacheRead * multiplier; acc.peakOutput += tally.output * multiplier
            acc.cost += tokenCost(
                model: tally.model, input: tally.input,
                cacheCreate: tally.cacheCreate, cacheRead: tally.cacheRead, output: tally.output
            )
        }
        return acc
    }
}
