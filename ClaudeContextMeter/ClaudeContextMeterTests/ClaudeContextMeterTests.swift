//
//  ClaudeContextMeterTests.swift
//  ClaudeContextMeterTests
//
//  Created by Scott Bly on 4/3/26.
//

import XCTest
@testable import ClaudeContextMeter

final class ClaudeContextMeterTests: XCTestCase {

    // Isolate every test from the user's real preferences (claude-context-meter-8ax). Tests
    // used to write/removeObject on the shared prod UserDefaults domain, which deleted live
    // selectedPlan/billingTokenLimit values on any run. Route all app UserDefaults access
    // (AppPreferences.store) through a per-test throwaway suite instead.
    private var testSuiteName: String!
    override func setUp() {
        super.setUp()
        testSuiteName = "com.scottbly.ClaudeContextMeter.tests.\(UUID().uuidString)"
        AppPreferences.store = UserDefaults(suiteName: testSuiteName)!
    }
    override func tearDown() {
        AppPreferences.store.removePersistentDomain(forName: testSuiteName)
        AppPreferences.store = .standard
        testSuiteName = nil
        super.tearDown()
    }

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

    // MARK: - ModelLimits (deterministic model → context window)
    //
    // `contextWindow(for:observedInputTokens:)` takes the INPUT-side token sum (input +
    // cache_creation + cache_read), excluding output — see UsageTokens.inputSideTokens and the
    // calculator-level test testHaikuAtInputCapWithOutputStays200k, which proves output can no
    // longer falsely promote a maxed-out 200k model to /1M.

    /// The bug this fix targets: a 1M-capable model sitting *below* 200k tokens must still
    /// report the 1M denominator. The old reactive design pinned it to 200k until it observed
    /// >200k, so a real opus-4-8 session at 178k showed 178k/200k (89%) instead of /1M (18%).
    func testExtendedModelUnder200kReturns1M() {
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-opus-4-8", observedInputTokens: 178_694),
            1_000_000,
            "A 1M model below 200k tokens must still use the 1M denominator"
        )
    }

    /// Opus 5 (released 2026-07-23, verified via platform.claude.com) is a 1M-capable model.
    func testOpus5Returns1M() {
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-opus-5", observedInputTokens: 50_000),
            1_000_000)
    }

    /// Pins the FULL expected map by literal value, so a silent drop or mis-map of any single
    /// model is caught (the derived-Set tests below only prove internal agreement, not that the
    /// map itself is correct/complete). Update deliberately when the shipped lineup changes.
    func testContextWindowMapMatchesExpectedLineup() {
        let expected: [String: Int64] = [
            "claude-opus-5": 1_000_000,
            "claude-opus-4-6": 1_000_000,
            "claude-opus-4-7": 1_000_000,
            "claude-opus-4-8": 1_000_000,
            "claude-sonnet-4-6": 1_000_000,
            "claude-sonnet-5": 1_000_000,
            "claude-fable-5": 1_000_000,
            "claude-mythos-5": 1_000_000,
            "claude-haiku-4-5": 200_000
        ]
        XCTAssertEqual(ModelLimits.contextWindowByModel, expected,
                       "Shipped model→window map drifted from the expected lineup")
    }

    /// Every current 1M-capable model returns 1M regardless of observed input. Reads the
    /// production map so the test can't drift out of sync with the shipped lineup.
    func testAllExtendedContextModelsReturn1MAtAnyTokenCount() {
        for model in ModelLimits.extendedContextModels {
            XCTAssertEqual(
                ModelLimits.contextWindow(for: model, observedInputTokens: 10_000),
                1_000_000, "\(model) should report 1M even at low input counts")
            XCTAssertEqual(
                ModelLimits.contextWindow(for: model, observedInputTokens: 900_000),
                1_000_000, "\(model) should report 1M at high input counts")
        }
    }

    func testHaiku45StaysAt200kUpToItsInputCap() {
        // Haiku 4.5 is the only current 200k model. Because the input side is what a model can
        // physically hold and it's capped at the 200k window, a real Haiku session's input side
        // never exceeds 200k — so the safety net correctly never promotes it. (Output tokens,
        // which used to be included and could tip a maxed session past 200k, are excluded now;
        // see testHaikuAtInputCapWithOutputStays200k for the end-to-end proof.)
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-haiku-4-5", observedInputTokens: 150_000),
            200_000)
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-haiku-4-5", observedInputTokens: 200_000),
            200_000)
    }

    func testUnknownModelDefaultsTo200k() {
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-future-model-xyz", observedInputTokens: 0),
            200_000)
    }

    /// Upward-only safety net: a model not in the map (or mapped low) whose *input side* exceeds
    /// 200k must actually be running a larger window, so promote it to 1M. Includes the exact
    /// `>` boundary (200_001) to lock the comparison operator.
    func testUnmappedModelInputOver200kPromotesTo1M() {
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-future-model-xyz", observedInputTokens: 200_001),
            1_000_000, "just over 200k input must promote (locks the `>` boundary)")
        XCTAssertEqual(
            ModelLimits.contextWindow(for: "claude-future-model-xyz", observedInputTokens: 250_000),
            1_000_000)
    }

    /// `extendedContextModels` is derived from `contextWindowByModel`, so it can't silently
    /// drift from the shipped data. Opus 5 in; Haiku (the one 200k current model) out.
    func testExtendedContextModelsDerivedFromMap() {
        XCTAssertTrue(ModelLimits.extendedContextModels.contains("claude-opus-5"))
        XCTAssertTrue(ModelLimits.extendedContextModels.contains("claude-opus-4-8"))
        XCTAssertFalse(ModelLimits.extendedContextModels.contains("claude-haiku-4-5"))
    }

    // MARK: - Weekly reset configuration (Settings)

    /// Locks the Settings time labels (claude-context-meter-va6). Midnight/noon are the
    /// error-prone cases; 21→"9:00 PM" is Scott's mismatch (Claude shows Tue 12:00 PM).
    func testSettingsHourLabelFormatsOnTheHourAmPm() {
        XCTAssertEqual(SettingsView.hourLabel(0),  "12:00 AM")
        XCTAssertEqual(SettingsView.hourLabel(9),  "9:00 AM")
        XCTAssertEqual(SettingsView.hourLabel(12), "12:00 PM")
        XCTAssertEqual(SettingsView.hourLabel(21), "9:00 PM")
        XCTAssertEqual(SettingsView.hourLabel(23), "11:00 PM")
    }

    /// Locks the 1=Sunday…7=Saturday Calendar-weekday mapping used by the reset-day picker,
    /// so weekday 3 is Tuesday (the value that must correspond to Claude's "Tue" reset).
    func testSettingsWeekdayNameMapsCalendarWeekday() {
        let symbols = Calendar.current.weekdaySymbols
        XCTAssertEqual(SettingsView.weekdayName(1), symbols[0])
        XCTAssertEqual(SettingsView.weekdayName(3), symbols[2])
        XCTAssertEqual(SettingsView.weekdayName(7), symbols[6])
    }

    /// The whole point of the feature: a user-set weekday/hour is honored by the calculator.
    /// (Runs against the isolated test suite, so it doesn't touch real prefs.)
    func testWeeklyCalculatorHonorsConfiguredWeekdayAndHour() {
        AppPreferences.store.set(3, forKey: WeeklyUsageCalculator.weekdayKey)   // Tuesday
        AppPreferences.store.set(12, forKey: WeeklyUsageCalculator.hourKey)     // noon
        XCTAssertEqual(WeeklyUsageCalculator.resetWeekday, 3)
        XCTAssertEqual(WeeklyUsageCalculator.resetHour, 12)
    }

    /// With nothing configured, the calculator falls back to the same defaults the Settings
    /// pickers seed (Tue 21:00), so the shipped default and the UI agree.
    func testWeeklyCalculatorDefaultsMatchSettingsDefaults() {
        AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
        AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.hourKey)
        XCTAssertEqual(WeeklyUsageCalculator.resetWeekday, WeeklyUsageCalculator.defaultWeekday)
        XCTAssertEqual(WeeklyUsageCalculator.resetHour, WeeklyUsageCalculator.defaultHour)
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

    func testBillingCalculateFilesEmptyReturnsZeroTokens() {
        let result = BillingWindowCalculator.calculate(files: [])
        XCTAssertEqual(result.outputTokens, 0)
    }

    func testBillingCalculateFilesMatchesCalculateNoArg() {
        let now = Date()
        let lookback = now.addingTimeInterval(-10 * 3600)
        let fileModifiedSince = lookback.addingTimeInterval(-1 * 3600)
        let files = JSONLParser.allSessionFiles(modifiedSince: fileModifiedSince)
        let fromFiles = BillingWindowCalculator.calculate(files: files)
        let fromNoArg = BillingWindowCalculator.calculate()
        XCTAssertEqual(fromFiles.outputTokens, fromNoArg.outputTokens)
        XCTAssertEqual(fromFiles.tokenLimit,   fromNoArg.tokenLimit)
    }

    func testBillingCalculateRecordsMatchesCalculateFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("billing_records_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = """
        {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"\(formatter.string(from: now))","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let viaFiles = BillingWindowCalculator.calculate(files: [file])
        let records = try JSONLParser.parse(fileURL: file)
        let viaRecords = BillingWindowCalculator.calculate(records: records)

        XCTAssertEqual(viaFiles.outputTokens, viaRecords.outputTokens)
        XCTAssertEqual(viaFiles.windowStart, viaRecords.windowStart)
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
        AppPreferences.store.set(3,  forKey: WeeklyUsageCalculator.weekdayKey)
        AppPreferences.store.set(21, forKey: WeeklyUsageCalculator.hourKey)
        defer {
            AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
            AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.hourKey)
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

        AppPreferences.store.set(3,  forKey: WeeklyUsageCalculator.weekdayKey)
        AppPreferences.store.set(21, forKey: WeeklyUsageCalculator.hourKey)
        defer {
            AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
            AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.hourKey)
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

        AppPreferences.store.set(3,  forKey: WeeklyUsageCalculator.weekdayKey)
        AppPreferences.store.set(21, forKey: WeeklyUsageCalculator.hourKey)
        defer {
            AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.weekdayKey)
            AppPreferences.store.removeObject(forKey: WeeklyUsageCalculator.hourKey)
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

    func testWeeklyCalculateFilesEmptyReturnsZeroTokens() {
        let result = WeeklyUsageCalculator.calculate(files: [])
        XCTAssertEqual(result.allTokens, 0)
        XCTAssertEqual(result.noCacheRead, 0)
        XCTAssertEqual(result.inputOutputOnly, 0)
    }

    func testWeeklyCalculateFilesMatchesCalculateNoArg() {
        let windowStart = WeeklyUsageCalculator.findWeeklyWindowStart()
        let files = JSONLParser.allSessionFiles(modifiedSince: windowStart)
        let fromFiles = WeeklyUsageCalculator.calculate(files: files)
        let fromNoArg = WeeklyUsageCalculator.calculate()
        XCTAssertEqual(fromFiles.allTokens,       fromNoArg.allTokens)
        XCTAssertEqual(fromFiles.noCacheRead,     fromNoArg.noCacheRead)
        XCTAssertEqual(fromFiles.inputOutputOnly, fromNoArg.inputOutputOnly)
    }

    func testWeeklyCalculateRecordsMatchesCalculateFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly_records_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = """
        {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"\(formatter.string(from: now))","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let viaFiles = WeeklyUsageCalculator.calculate(files: [file])
        let records = try JSONLParser.parse(fileURL: file)
        let viaRecords = WeeklyUsageCalculator.calculate(records: records)

        XCTAssertEqual(viaFiles.allTokens, viaRecords.allTokens)
        XCTAssertEqual(viaFiles.windowStart, viaRecords.windowStart)
    }

    // MARK: - ContextWindowCalculator.calculate(mostRecentFile:)

    func testContextCalculateMostRecentFileNilReturnsNil() {
        let result = ContextWindowCalculator.calculate(mostRecentFile: nil)
        XCTAssertNil(result)
    }

    func testContextCalculateMostRecentFileMatchesCalculateNoArg() throws {
        // Call calculate(mostRecentFile:) twice with the same URL to verify idempotency.
        // Comparing to the no-arg overload would race: a live session can produce a newer
        // file between the two calls, causing them to return different results.
        guard let url = JSONLParser.mostRecentSessionFile() else {
            throw XCTSkip("No session files available — skipping live-file test")
        }
        let a = ContextWindowCalculator.calculate(mostRecentFile: url)
        let b = ContextWindowCalculator.calculate(mostRecentFile: url)
        XCTAssertEqual(a?.totalTokens,  b?.totalTokens)
        XCTAssertEqual(a?.contextLimit, b?.contextLimit)
    }

    func testContextCalculateRecordsMatchesCalculateMostRecentFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("context_records_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        let line = """
        {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"2026-07-12T10:00:00.000Z","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let viaFile = ContextWindowCalculator.calculate(mostRecentFile: file)
        let records = try JSONLParser.parse(fileURL: file)
        let viaRecords = ContextWindowCalculator.calculate(mostRecentFile: file, records: records)

        XCTAssertEqual(viaFile?.totalTokens, viaRecords?.totalTokens)
        XCTAssertEqual(viaFile?.model, viaRecords?.model)
    }

    func testContextCalculateRecordsNilFileReturnsNil() {
        XCTAssertNil(ContextWindowCalculator.calculate(mostRecentFile: nil, records: []))
    }

    /// Regression for the output-token over-report: a genuine 200k model (Haiku 4.5) whose
    /// INPUT side sits at the 200k cap and then generates a large output must keep the 200k
    /// denominator — not be falsely promoted to /1M. Before the fix the safety net compared
    /// totalTokens (input + output = 260k > 200k) and wrongly returned 1M, under-stating usage
    /// ~5x at the exact moment the user is maxed out.
    func testHaikuAtInputCapWithOutputStays200k() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("context_haiku_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        // input-side = 200_000 (at the cap); output = 60_000 on top → totalTokens = 260_000.
        let line = """
        {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"2026-07-25T10:00:00.000Z","message":{"model":"claude-haiku-4-5","stop_reason":"end_turn","usage":{"input_tokens":150000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":40000,"output_tokens":60000}}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let records = try JSONLParser.parse(fileURL: file)
        let metrics = ContextWindowCalculator.calculate(mostRecentFile: file, records: records)

        XCTAssertEqual(metrics?.contextLimit, 200_000,
                       "Output tokens must not promote a maxed-out 200k model to /1M")
        XCTAssertEqual(metrics?.totalTokens, 260_000,
                       "Numerator still counts total tokens incl. output (denominator is the fix)")
    }

    // MARK: - JSONLParser.scanAllFiles

    func testScanAllFilesOnEmptyDirectoryReturnsNilAndEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_empty_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = JSONLParser.scanAllFiles(relativeTo: Date(), projectsDir: tempDir)
        XCTAssertNil(result.mostRecent)
        XCTAssertTrue(result.billingFiles.isEmpty)
        XCTAssertTrue(result.weeklyFiles.isEmpty)
    }

    func testScanAllFilesIgnoresNonJsonlFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_nojsonl_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let txtFile = tempDir.appendingPathComponent("session.txt")
        try "data".write(to: txtFile, atomically: true, encoding: .utf8)

        let result = JSONLParser.scanAllFiles(relativeTo: Date(), projectsDir: tempDir)
        XCTAssertNil(result.mostRecent)
        XCTAssertTrue(result.billingFiles.isEmpty)
    }

    func testScanAllFilesMostRecentExcludesSubagents() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_subagent_\(ProcessInfo.processInfo.globallyUniqueString)")
        let subagentDir = tempDir.appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagentDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mainFile = tempDir.appendingPathComponent("main.jsonl")
        let subagentFile = subagentDir.appendingPathComponent("sub.jsonl")
        try "{}".write(to: mainFile, atomically: true, encoding: .utf8)
        try "{}".write(to: subagentFile, atomically: true, encoding: .utf8)

        let future = Date().addingTimeInterval(3600)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: subagentFile.path)

        let result = JSONLParser.scanAllFiles(relativeTo: Date(), projectsDir: tempDir)
        XCTAssertEqual(result.mostRecent?.lastPathComponent, "main.jsonl",
                       "mostRecent must never be a file inside a subagents/ directory")
    }

    func testScanAllFilesBillingCutoffIs11Hours() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_billing_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date()
        let recent = tempDir.appendingPathComponent("recent.jsonl")
        let old    = tempDir.appendingPathComponent("old.jsonl")
        try "{}".write(to: recent, atomically: true, encoding: .utf8)
        try "{}".write(to: old,    atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 3600)],
                                              ofItemAtPath: recent.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-12 * 3600)],
                                              ofItemAtPath: old.path)

        let result = JSONLParser.scanAllFiles(relativeTo: now, projectsDir: tempDir)
        let billingNames = result.billingFiles.map(\.lastPathComponent)
        XCTAssertTrue(billingNames.contains("recent.jsonl"),
                      "File modified 10h ago should be inside the 11h billing window")
        XCTAssertFalse(billingNames.contains("old.jsonl"),
                       "File modified 12h ago should be outside the 11h billing window")
    }

    // MARK: - RefreshCoordinator

    func testCoordinatorFirstCallReturnsResult() async {
        let coordinator = RefreshCoordinator()
        let result = await coordinator.refresh()
        XCTAssertNotNil(result, "First call should never be debounced")
    }

    func testCoordinatorImmediateSecondCallIsDebounced() async {
        let coordinator = RefreshCoordinator()
        _ = await coordinator.refresh()           // first call — runs
        let second = await coordinator.refresh()  // immediate second call — debounced
        XCTAssertNil(second, "Call within minimumInterval should return nil (debounced)")
    }

    func testCoordinatorCallAfterIntervalIsNotDebounced() async throws {
        let coordinator = RefreshCoordinator(minimumInterval: 0.01)
        _ = await coordinator.refresh()
        try await Task.sleep(nanoseconds: 20_000_000)  // 20ms > 10ms interval
        let second = await coordinator.refresh()
        XCTAssertNotNil(second, "Call after minimumInterval should not be debounced")
    }

    func testCoordinatorDoesNotReparseUnchangedFileAcrossRefreshes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coord_cache_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = """
        {"type":"assistant","requestId":"req_1","sessionId":"s1","timestamp":"\(formatter.string(from: now))","message":{"model":"claude-opus-4-8","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":20}}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let coordinator = RefreshCoordinator(minimumInterval: 0, projectsDir: tempDir)
        _ = await coordinator.refresh()
        let billingAfterFirst = await coordinator.refresh()

        XCTAssertNotNil(billingAfterFirst, "Second call after interval elapses should not be debounced")
        XCTAssertEqual(billingAfterFirst?.billing.outputTokens, 20,
                       "Unchanged file must still be reflected correctly on a cache-hit refresh")
    }

    // MARK: - JSONLParseCache

    func testParseCacheFirstCallInvokesParseOnce() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_first_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        var callCount = 0
        let cache = JSONLParseCache { _ in
            callCount += 1
            return []
        }

        _ = cache.records(for: file)
        XCTAssertEqual(callCount, 1, "First call for a URL must invoke parse exactly once")
    }

    func testParseCacheUnchangedFileIsNotReparsed() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_unchanged_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        var callCount = 0
        let cache = JSONLParseCache { _ in
            callCount += 1
            return []
        }

        _ = cache.records(for: file)
        _ = cache.records(for: file)
        XCTAssertEqual(callCount, 1, "Second call for an unchanged file must be a cache hit (no reparse)")
    }

    func testParseCacheChangedModificationDateReparsesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_mtime_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var file = tempDir.appendingPathComponent("session.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        var callCount = 0
        let cache = JSONLParseCache { _ in
            callCount += 1
            return []
        }

        _ = cache.records(for: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3600)],
            ofItemAtPath: file.path
        )
        // URL caches resource values (mtime/size) it has already read, so re-reading the
        // SAME URL value after mutating the file on disk would return the stale cached
        // snapshot rather than the new state. Invalidate it to simulate what production
        // sees: RefreshCoordinator always hands the cache freshly-enumerated URLs, which
        // carry no stale cache.
        file.removeAllCachedResourceValues()
        _ = cache.records(for: file)
        XCTAssertEqual(callCount, 2, "A changed modification date must trigger a reparse")
    }

    func testParseCacheChangedSizeReparsesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_size_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var file = tempDir.appendingPathComponent("session.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)
        let fixedDate = Date()
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: file.path)

        var callCount = 0
        let cache = JSONLParseCache { _ in
            callCount += 1
            return []
        }

        _ = cache.records(for: file)
        try "{}\n{}".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: file.path)
        // See comment in testParseCacheChangedModificationDateReparsesFile: URL caches
        // resource values it has already read, so this must be invalidated after the
        // on-disk mutation or the second records(for:) call will see stale size/mtime.
        file.removeAllCachedResourceValues()
        _ = cache.records(for: file)
        XCTAssertEqual(callCount, 2, "A changed file size (same mtime) must trigger a reparse")
    }

    func testParseCachePruneEvictsUnkeptURLs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_prune_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        var callCount = 0
        let cache = JSONLParseCache { _ in
            callCount += 1
            return []
        }

        _ = cache.records(for: file)
        cache.prune(keeping: [])
        _ = cache.records(for: file)
        XCTAssertEqual(callCount, 2, "Pruning a URL out of the cache must force a reparse on next access")
    }

    func testParseCacheParseFailureIsNotCached() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache_failure_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("session.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        var callCount = 0
        let cache = JSONLParseCache { _ in
            callCount += 1
            throw NSError(domain: "test", code: 1)
        }

        let first = cache.records(for: file)
        let second = cache.records(for: file)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(callCount, 2, "A parse failure must not be cached — every call should retry")
    }

    // MARK: - ClaudeContextMeterApp.isRunningUnderTests

    func testIsRunningUnderTestsIsTrueDuringXCTestRun() {
        // This test itself runs inside an XCTest host, so XCTestConfigurationFilePath
        // is genuinely set in the environment — this exercises the real detection path,
        // not a mock.
        XCTAssertTrue(ClaudeContextMeterApp.isRunningUnderTests,
                      "XCTestConfigurationFilePath must be present in the environment during any XCTest run")
    }

}

// MARK: - ClaudePlan

final class ClaudePlanTests: XCTestCase {

    // Same prod-prefs isolation as ClaudeContextMeterTests (claude-context-meter-8ax): a
    // throwaway suite per test so ClaudePlan.save()/.current never touch the real domain.
    private var testSuiteName: String!
    override func setUp() {
        super.setUp()
        testSuiteName = "com.scottbly.ClaudeContextMeter.tests.\(UUID().uuidString)"
        AppPreferences.store = UserDefaults(suiteName: testSuiteName)!
    }
    override func tearDown() {
        AppPreferences.store.removePersistentDomain(forName: testSuiteName)
        AppPreferences.store = .standard
        testSuiteName = nil
        super.tearDown()
    }

    /// Enforces claude-context-meter-8ax: tests must run against the throwaway suite, never the
    /// shared production domain. If this fails, a test run could delete the user's live prefs.
    func testTestsRunAgainstIsolatedStoreNotStandard() {
        XCTAssertNotEqual(AppPreferences.store, UserDefaults.standard,
                          "AppPreferences.store must be a throwaway suite during tests")
    }

    func testProLabelAndLimit() {
        XCTAssertEqual(ClaudePlan.pro.label, "Pro")
        XCTAssertEqual(ClaudePlan.pro.tokenLimit, 131_000)
    }

    func testMax5xLabelAndLimit() {
        XCTAssertEqual(ClaudePlan.max5x.label, "Max 5x")
        XCTAssertEqual(ClaudePlan.max5x.tokenLimit, 655_000)
    }

    func testMax20xLabelAndLimit() {
        XCTAssertEqual(ClaudePlan.max20x.label, "Max 20x")
        XCTAssertEqual(ClaudePlan.max20x.tokenLimit, 2_620_000)
    }

    func testAllCasesHasThreePlans() {
        XCTAssertEqual(ClaudePlan.allCases.count, 3)
    }

    func testCurrentDefaultsToProWhenNothingStored() {
        AppPreferences.store.removeObject(forKey: ClaudePlan.planKey)
        XCTAssertEqual(ClaudePlan.current, .pro)
    }

    func testCurrentReadsStoredPlan() {
        AppPreferences.store.set("max5x", forKey: ClaudePlan.planKey)
        XCTAssertEqual(ClaudePlan.current, .max5x)
    }

    func testCurrentFallsBackToProForUnknownRaw() {
        AppPreferences.store.set("enterprise", forKey: ClaudePlan.planKey)
        XCTAssertEqual(ClaudePlan.current, .pro)
    }

    func testSaveWritesBothKeys() {
        ClaudePlan.max5x.save()
        XCTAssertEqual(AppPreferences.store.string(forKey: ClaudePlan.planKey), "max5x")
        XCTAssertEqual(AppPreferences.store.integer(forKey: BillingWindowCalculator.limitKey), 655_000)
    }

    func testSaveMax20xWritesCorrectLimit() {
        ClaudePlan.max20x.save()
        XCTAssertEqual(AppPreferences.store.string(forKey: ClaudePlan.planKey), "max20x")
        XCTAssertEqual(AppPreferences.store.integer(forKey: BillingWindowCalculator.limitKey), 2_620_000)
    }
}
