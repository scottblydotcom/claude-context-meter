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
        let usage = try JSONDecoder().decode(SessionRecord.UsageTokens.self, from: data)

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
        let usage = try JSONDecoder().decode(SessionRecord.UsageTokens.self, from: data)

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

    // MARK: - BillingWindowCalculator window boundary math

    func testWindowStartIsAnchorDuringFirstPeriod() {
        // Anchor is 3 hours ago → we are still in the first 5-hour window.
        // Expected window start = anchor (periods = floor(3/5) = 0).
        let anchor = Date().addingTimeInterval(-3 * 3600)
        BillingWindowCalculator.windowAnchor = anchor
        defer { UserDefaults.standard.removeObject(forKey: BillingWindowCalculator.anchorKey) }

        let windowStart = BillingWindowCalculator.currentWindowStart()
        XCTAssertEqual(windowStart.timeIntervalSince1970, anchor.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWindowStartAdvancesAfterOnePeriod() {
        // Anchor is 7 hours ago → one full 5-hour window has elapsed.
        // Expected window start = anchor + 5h (periods = floor(7/5) = 1).
        let anchor = Date().addingTimeInterval(-7 * 3600)
        BillingWindowCalculator.windowAnchor = anchor
        defer { UserDefaults.standard.removeObject(forKey: BillingWindowCalculator.anchorKey) }

        let expected = anchor.addingTimeInterval(5 * 3600)
        let windowStart = BillingWindowCalculator.currentWindowStart()
        XCTAssertEqual(windowStart.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWindowStartAdvancesAfterTwoPeriods() {
        // Anchor is 11 hours ago → two full 5-hour windows have elapsed.
        // Expected window start = anchor + 10h (periods = floor(11/5) = 2).
        let anchor = Date().addingTimeInterval(-11 * 3600)
        BillingWindowCalculator.windowAnchor = anchor
        defer { UserDefaults.standard.removeObject(forKey: BillingWindowCalculator.anchorKey) }

        let expected = anchor.addingTimeInterval(10 * 3600)
        let windowStart = BillingWindowCalculator.currentWindowStart()
        XCTAssertEqual(windowStart.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }
}
