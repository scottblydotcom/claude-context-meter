//
//  SessionRecord.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

/// One line of a Claude JSONL session log file.
struct SessionRecord: Codable {
    let type: String           // "assistant" or "user"
    let requestId: String?
    let sessionId: String?
    let timestamp: String
    let message: MessageContent?

    struct MessageContent: Codable {
        let model: String?
        let stopReason: String?  // null during streaming, "end_turn" when complete
        let usage: UsageTokens?

        enum CodingKeys: String, CodingKey {
            case model
            case stopReason = "stop_reason"
            case usage
        }
    }

    struct UsageTokens: Codable {
        let inputTokens: Int
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
        }

        /// Total tokens consumed in this turn (input + cache + output).
        var totalTokens: Int {
            inputTokens + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0) + outputTokens
        }
    }

    /// True when this is a complete (non-streaming) assistant record with token data.
    var isCompleteAssistantRecord: Bool {
        type == "assistant" &&
        message?.stopReason != nil &&
        (message?.usage?.outputTokens ?? 0) > 0
    }
}
