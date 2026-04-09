//
//  ClaudeContextMeterTests.swift
//  ClaudeContextMeterTests
//
//  Created by Scott Bly on 4/3/26.
//

import XCTest
@testable import ClaudeContextMeter

final class ClaudeContextMeterTests: XCTestCase {

    // MARK: - SessionRecord decoding

    func testDecodesCompleteAssistantRecord() throws {
        let json = """
        {
            "type": "assistant",
            "requestId": "req_abc123",
            "sessionId": "sess_xyz",
            "timestamp": "2026-04-03T20:00:00.000Z",
            "message": {
                "model": "claude-sonnet-4-6",
                "stop_reason": "end_turn",
                "usage": {
                    "input_tokens": 1000,
                    "cache_creation_input_tokens": 500,
                    "cache_read_input_tokens": 2000,
                    "output_tokens": 300
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)

        XCTAssertEqual(record.type, "assistant")
        XCTAssertEqual(record.message?.stopReason, "end_turn")
        XCTAssertEqual(record.message?.usage?.outputTokens, 300)
        XCTAssertEqual(record.message?.usage?.totalTokens, 3800)
        XCTAssertTrue(record.isCompleteAssistantRecord)
    }

    func testStreamingRecordIsNotComplete() throws {
        let json = """
        {
            "type": "assistant",
            "requestId": "req_abc123",
            "sessionId": "sess_xyz",
            "timestamp": "2026-04-03T20:00:00.000Z",
            "message": {
                "model": "claude-sonnet-4-6",
                "stop_reason": null,
                "usage": {
                    "input_tokens": 1000,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "output_tokens": 6
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)

        XCTAssertFalse(record.isCompleteAssistantRecord)
    }

    func testUserRecordIsNotComplete() throws {
        let json = """
        {
            "type": "user",
            "requestId": null,
            "sessionId": "sess_xyz",
            "timestamp": "2026-04-03T20:00:00.000Z",
            "message": null
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)

        XCTAssertFalse(record.isCompleteAssistantRecord)
    }

    /// An assistant record with a stop_reason but zero output tokens is still
    /// considered incomplete — it's a degenerate streaming partial.
    func testAssistantRecordWithZeroOutputTokensIsNotComplete() throws {
        let json = """
        {
            "type": "assistant",
            "requestId": "req_abc123",
            "sessionId": "sess_xyz",
            "timestamp": "2026-04-03T20:00:00.000Z",
            "message": {
                "model": "claude-sonnet-4-6",
                "stop_reason": "end_turn",
                "usage": {
                    "input_tokens": 500,
                    "output_tokens": 0
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)

        XCTAssertFalse(record.isCompleteAssistantRecord)
    }

    // MARK: - UsageTokens.totalTokens

    func testTotalTokensWithAllCacheFields() throws {
        let json = """
        {
            "input_tokens": 1000,
            "cache_creation_input_tokens": 500,
            "cache_read_input_tokens": 2000,
            "output_tokens": 300
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let usage = try JSONDecoder().decode(UsageTokens.self, from: data)

        // 1000 + 500 + 2000 + 300 = 3800
        XCTAssertEqual(usage.totalTokens, 3800)
    }

    func testTotalTokensWithNilCacheFields() throws {
        // JSONL records don't always include cache fields — they should default to 0.
        let json = """
        {
            "input_tokens": 1000,
            "output_tokens": 300
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let usage = try JSONDecoder().decode(UsageTokens.self, from: data)

        // 1000 + 0 + 0 + 300 = 1300
        XCTAssertEqual(usage.totalTokens, 1300)
    }

    // MARK: - ModelLimits

    func testKnownClaudeModelsReturn200k() {
        XCTAssertEqual(ModelLimits.contextWindow(for: "claude-sonnet-4-6"), 200_000)
        XCTAssertEqual(ModelLimits.contextWindow(for: "claude-opus-4-6"), 200_000)
        XCTAssertEqual(ModelLimits.contextWindow(for: "claude-haiku-4-5"), 200_000)
    }

    func testUnknownModelReturnsDefault() {
        XCTAssertEqual(ModelLimits.contextWindow(for: "gpt-4"), 200_000)
    }

    // MARK: - JSONLParser

    func testParsesValidJSONLFile() throws {
        let lines = [
            """
            {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"2026-04-03T20:00:00.000Z","message":{"model":"claude-sonnet-4-6","stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
            """,
            """
            {"type":"user","requestId":null,"sessionId":"s1","timestamp":"2026-04-03T20:01:00.000Z","message":null}
            """,
            "this line is malformed JSON and should be silently skipped"
        ]

        let content = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let records = try JSONLParser.parse(fileURL: url)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].type, "assistant")
        XCTAssertEqual(records[1].type, "user")
    }

    func testDeduplicatesByRequestId() throws {
        // Same requestId appearing 3 times (streaming partials) — only one should be used
        let sameRequest = """
        {"type":"assistant","requestId":"req_dup","sessionId":"s1","timestamp":"2026-04-03T20:00:00.000Z","message":{"model":"claude-sonnet-4-6","stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        let content = [sameRequest, sameRequest, sameRequest].joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_dup.jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let records = try JSONLParser.parse(fileURL: url)
        let unique = Dictionary(grouping: records, by: \.requestId).values.compactMap(\.first)

        XCTAssertEqual(unique.count, 1)
    }

    func testEmptyFileReturnsNoRecords() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty.jsonl")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let records = try JSONLParser.parse(fileURL: url)
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - ContextWindowMetrics.fillPercent

    func testFillPercentAtQuarter() {
        let metrics = ContextWindowMetrics(
            fileName: "test.jsonl",
            model: "claude-sonnet-4-6",
            totalTokens: 50_000,
            contextLimit: 200_000,
            inputTokens: 48_000,
            cacheReadTokens: 1_000,
            outputTokens: 1_000
        )
        XCTAssertEqual(metrics.fillPercent, 25)
    }

    func testFillPercentAtHalf() {
        let metrics = ContextWindowMetrics(
            fileName: "test.jsonl",
            model: "claude-sonnet-4-6",
            totalTokens: 100_000,
            contextLimit: 200_000,
            inputTokens: 99_000,
            cacheReadTokens: 0,
            outputTokens: 1_000
        )
        XCTAssertEqual(metrics.fillPercent, 50)
    }

    func testFillPercentAtFull() {
        let metrics = ContextWindowMetrics(
            fileName: "test.jsonl",
            model: "claude-sonnet-4-6",
            totalTokens: 200_000,
            contextLimit: 200_000,
            inputTokens: 199_000,
            cacheReadTokens: 0,
            outputTokens: 1_000
        )
        XCTAssertEqual(metrics.fillPercent, 100)
    }

    func testFillPercentZeroTotalTokens() {
        let metrics = ContextWindowMetrics(
            fileName: "test.jsonl",
            model: "claude-sonnet-4-6",
            totalTokens: 0,
            contextLimit: 200_000,
            inputTokens: 0,
            cacheReadTokens: 0,
            outputTokens: 0
        )
        XCTAssertEqual(metrics.fillPercent, 0)
    }

    func testFillPercentZeroLimitReturnsZero() {
        // Guard against divide-by-zero.
        let metrics = ContextWindowMetrics(
            fileName: "test.jsonl",
            model: "unknown",
            totalTokens: 1_000,
            contextLimit: 0,
            inputTokens: 1_000,
            cacheReadTokens: 0,
            outputTokens: 0
        )
        XCTAssertEqual(metrics.fillPercent, 0)
    }

    // MARK: - BillingWindowMetrics.fillPercent

    func testBillingFillPercentAtHalf() {
        let now = Date()
        let metrics = BillingWindowMetrics(
            outputTokens: 65_500,
            tokenLimit: 131_000,
            windowStart: now,
            nextReset: now.addingTimeInterval(5 * 3600)
        )
        XCTAssertEqual(metrics.fillPercent, 50)
    }

    func testBillingFillPercentAtFull() {
        let now = Date()
        let metrics = BillingWindowMetrics(
            outputTokens: 131_000,
            tokenLimit: 131_000,
            windowStart: now,
            nextReset: now.addingTimeInterval(5 * 3600)
        )
        XCTAssertEqual(metrics.fillPercent, 100)
    }

    func testBillingFillPercentZeroLimitReturnsZero() {
        let now = Date()
        let metrics = BillingWindowMetrics(
            outputTokens: 1_000,
            tokenLimit: 0,
            windowStart: now,
            nextReset: now.addingTimeInterval(5 * 3600)
        )
        XCTAssertEqual(metrics.fillPercent, 0)
    }

    // MARK: - BillingWindowMetrics.timeUntilReset

    func testTimeUntilResetShowsHoursAndMinutes() {
        let now = Date()
        // Add 30s buffer so sub-second test execution doesn't flip the minute count.
        let metrics = BillingWindowMetrics(
            outputTokens: 0,
            tokenLimit: 131_000,
            windowStart: now,
            nextReset: now.addingTimeInterval(2 * 3600 + 30 * 60 + 30)
        )
        XCTAssertEqual(metrics.timeUntilReset, "2h 30m")
    }

    func testTimeUntilResetShowsMinutesOnlyWhenUnderOneHour() {
        let now = Date()
        // Add 30s buffer so sub-second test execution doesn't flip the minute count.
        let metrics = BillingWindowMetrics(
            outputTokens: 0,
            tokenLimit: 131_000,
            windowStart: now.addingTimeInterval(-4 * 3600),
            nextReset: now.addingTimeInterval(45 * 60 + 30)
        )
        XCTAssertEqual(metrics.timeUntilReset, "45m")
    }

    func testTimeUntilResetShowsZeroWhenExpired() {
        let past = Date().addingTimeInterval(-60) // already reset
        let metrics = BillingWindowMetrics(
            outputTokens: 0,
            tokenLimit: 131_000,
            windowStart: past.addingTimeInterval(-5 * 3600),
            nextReset: past
        )
        XCTAssertEqual(metrics.timeUntilReset, "0m")
    }

    // MARK: - BillingWindowCalculator rolling window math

    func testWindowStartWithSingleRecentRecord() {
        let now = Date()
        let ts = [now.addingTimeInterval(-1 * 3600)]  // 1h ago — active window
        let expected = Calendar.current.dateInterval(of: .hour, for: ts[0])!.start
        let start = BillingWindowCalculator.findWindowStart(from: ts, relativeTo: now)
        XCTAssertNotNil(start)
        XCTAssertEqual(start!.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    func testGapDefinesNewWindowStart() {
        let now = Date()
        let old    = now.addingTimeInterval(-7 * 3600)  // 7h ago — expired window
        let recent = now.addingTimeInterval(-1 * 3600)  // 1h ago — new window
        let expected = Calendar.current.dateInterval(of: .hour, for: recent)!.start
        let start = BillingWindowCalculator.findWindowStart(from: [old, recent], relativeTo: now)
        XCTAssertNotNil(start)
        XCTAssertEqual(start!.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWindowStartIsAnchoredToTopOfHour() {
        // A record at 41 minutes past the hour should anchor the window to the top of that hour.
        let calendar = Calendar.current
        let now = Date()
        let topOfHour = calendar.dateInterval(of: .hour, for: now.addingTimeInterval(-1 * 3600))!.start
        let recordAt41Min = topOfHour.addingTimeInterval(41 * 60)
        let start = BillingWindowCalculator.findWindowStart(from: [recordAt41Min], relativeTo: now)
        XCTAssertNotNil(start)
        XCTAssertEqual(start!.timeIntervalSince1970, topOfHour.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - WeeklyUsageCalculator window start

    func testWeeklyWindowStartOnResetDayAfterResetHour() {
        // Simulate: now = Tuesday at 10 PM, reset = Tuesday at 9 PM.
        // Expected: window started this Tuesday at 9 PM.
        let calendar = Calendar.current
        // Find the most recent Tuesday.
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 3  // Tuesday
        comps.hour = 22; comps.minute = 0; comps.second = 0
        guard let now = calendar.nextDate(after: Date().addingTimeInterval(-8 * 24 * 3600),
                                          matching: comps, matchingPolicy: .nextTime) else { return }

        var resetComps = calendar.dateComponents([.year, .month, .day], from: now)
        resetComps.hour = 21; resetComps.minute = 0; resetComps.second = 0
        let expectedStart = calendar.date(from: resetComps)!

        // Temporarily override UserDefaults to Tuesday 9 PM.
        UserDefaults.standard.set(3,  forKey: WeeklyUsageCalculator.weekdayKey)
        UserDefaults.standard.set(21, forKey: WeeklyUsageCalculator.hourKey)
        defer {
            UserDefaults.standard.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
            UserDefaults.standard.removeObject(forKey: WeeklyUsageCalculator.hourKey)
        }

        let start = WeeklyUsageCalculator.findWeeklyWindowStart(relativeTo: now)
        XCTAssertEqual(start.timeIntervalSince1970, expectedStart.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWeeklyWindowStartOnResetDayBeforeResetHour() {
        // Simulate: now = Tuesday at 8 PM, reset = Tuesday at 9 PM.
        // Expected: window started LAST Tuesday at 9 PM (not today).
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 3
        comps.hour = 20; comps.minute = 0; comps.second = 0
        guard let now = calendar.nextDate(after: Date().addingTimeInterval(-8 * 24 * 3600),
                                          matching: comps, matchingPolicy: .nextTime) else { return }

        // Expected: last Tuesday at 9 PM = now's Tuesday - 7 days, hour set to 21
        let lastTuesdaySameDay = calendar.date(byAdding: .day, value: -7, to: now)!
        var resetComps = calendar.dateComponents([.year, .month, .day], from: lastTuesdaySameDay)
        resetComps.hour = 21; resetComps.minute = 0; resetComps.second = 0
        let expectedStart = calendar.date(from: resetComps)!

        UserDefaults.standard.set(3,  forKey: WeeklyUsageCalculator.weekdayKey)
        UserDefaults.standard.set(21, forKey: WeeklyUsageCalculator.hourKey)
        defer {
            UserDefaults.standard.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
            UserDefaults.standard.removeObject(forKey: WeeklyUsageCalculator.hourKey)
        }

        let start = WeeklyUsageCalculator.findWeeklyWindowStart(relativeTo: now)
        XCTAssertEqual(start.timeIntervalSince1970, expectedStart.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWeeklyWindowStartOnNonResetDay() {
        // Simulate: now = Wednesday at noon, reset = Tuesday at 9 PM.
        // Expected: yesterday (Tuesday) at 9 PM.
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 4  // Wednesday
        comps.hour = 12; comps.minute = 0; comps.second = 0
        guard let now = calendar.nextDate(after: Date().addingTimeInterval(-8 * 24 * 3600),
                                          matching: comps, matchingPolicy: .nextTime) else { return }

        // Expected: the Tuesday just before this Wednesday, at 9 PM
        let tuesday = calendar.date(byAdding: .day, value: -1, to: now)!
        var resetComps = calendar.dateComponents([.year, .month, .day], from: tuesday)
        resetComps.hour = 21; resetComps.minute = 0; resetComps.second = 0
        let expectedStart = calendar.date(from: resetComps)!

        UserDefaults.standard.set(3,  forKey: WeeklyUsageCalculator.weekdayKey)
        UserDefaults.standard.set(21, forKey: WeeklyUsageCalculator.hourKey)
        defer {
            UserDefaults.standard.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
            UserDefaults.standard.removeObject(forKey: WeeklyUsageCalculator.hourKey)
        }

        let start = WeeklyUsageCalculator.findWeeklyWindowStart(relativeTo: now)
        XCTAssertEqual(start.timeIntervalSince1970, expectedStart.timeIntervalSince1970, accuracy: 1.0)
    }

    /// Window 1 expired at 11:00 AM. User came back at 12:23 PM (next hour).
    /// The new window should anchor to 12:00 PM, not 11:00 AM.
    /// Bug: the old cycling code used `windowStart = nextReset` (11:00 AM),
    /// then cycled again to 4:00 PM — massively undercounting tokens.
    func testCyclingAnchorsToFirstRecordInNewWindow() {
        let calendar = Calendar.current
        let now = Date()

        // Pin "now" to a known top-of-hour 6h in the future so arithmetic is clean.
        let base = calendar.dateInterval(of: .hour, for: now)!.start
            .addingTimeInterval(6 * 3600)

        // Window 1 first request: base - 6h47m → floor = base - 7h
        let w1Record1 = base.addingTimeInterval(-6 * 3600 - 47 * 60)
        // Window 1 second record: base - 5h30m (still in window 1)
        let w1Record2 = base.addingTimeInterval(-5 * 3600 - 30 * 60)
        // Window 1 expired at floor(w1Record1) + 5h = (base - 7h) + 5h = base - 2h
        // Window 2 first request: base - 1h37m → floor = base - 2h
        // (but first request is 23 min AFTER the reset, i.e., in the next hour slot)
        let w2Record1 = base.addingTimeInterval(-1 * 3600 - 37 * 60)
        let w2Record2 = base.addingTimeInterval(-30 * 60)

        let timestamps = [w1Record1, w1Record2, w2Record1, w2Record2].sorted()

        let expectedWindowStart = calendar.dateInterval(of: .hour, for: w2Record1)!.start

        let result = BillingWindowCalculator.findWindowStart(from: timestamps, relativeTo: base)
        XCTAssertNotNil(result, "Should find an active window")
        XCTAssertEqual(
            result!.timeIntervalSince1970,
            expectedWindowStart.timeIntervalSince1970,
            accuracy: 1.0,
            "Window 2 should anchor to the floor of the first record after window 1 expired"
        )
    }

    func testExpiredWindowReturnsNil() {
        let now = Date()
        let ts = [now.addingTimeInterval(-6 * 3600)]  // 6h ago — window expired
        let start = BillingWindowCalculator.findWindowStart(from: ts, relativeTo: now)
        XCTAssertNil(start)
    }

    // MARK: - WeeklyUsageCalculator.isPeakHour

    private func ptDate(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        // weekday: 1=Sun, 2=Mon … 7=Sat (Calendar convention)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // Find a recent date matching the target weekday.
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = weekday
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return cal.nextDate(after: Date().addingTimeInterval(-8 * 24 * 3600),
                            matching: comps, matchingPolicy: .nextTime)!
    }

    func testPeakHourMidMorningWeekday() {
        // Tuesday 8 AM PT — squarely in peak
        XCTAssertTrue(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 3, hour: 8)))
    }

    func testPeakHourBoundaryStartInclusive() {
        // Monday 5:00 AM PT — exactly at start, should be peak
        XCTAssertTrue(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 2, hour: 5, minute: 0)))
    }

    func testPeakHourBoundaryEndExclusive() {
        // Friday 11:00 AM PT — exactly at end, should NOT be peak
        XCTAssertFalse(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 6, hour: 11, minute: 0)))
    }

    func testPeakHourBefore5AM() {
        // Wednesday 4:59 AM PT — before peak window
        XCTAssertFalse(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 4, hour: 4, minute: 59)))
    }

    func testPeakHourAfternoonWeekday() {
        // Thursday 2 PM PT — after peak window
        XCTAssertFalse(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 5, hour: 14)))
    }

    func testPeakHourSaturdayDuringPeakWindow() {
        // Saturday 8 AM PT — peak time slot but weekend, should NOT be peak
        XCTAssertFalse(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 7, hour: 8)))
    }

    func testPeakHourSundayDuringPeakWindow() {
        // Sunday 9 AM PT — peak time slot but weekend, should NOT be peak
        XCTAssertFalse(WeeklyUsageCalculator.isPeakHour(ptDate(weekday: 1, hour: 9)))
    }
}
