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
}
