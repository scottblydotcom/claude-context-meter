//
//  SessionRecord.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

/// Plain data types nonisolated because this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`; without this, they'd implicitly inherit @MainActor and be unusable from
/// RefreshCoordinator (an actor) and the nonisolated calculators that parse/compute over them.
nonisolated struct MessageContent: Codable, Sendable {
    let model: String?
    let stopReason: String?  // null during streaming, "end_turn" when complete
    let usage: UsageTokens?

    enum CodingKeys: String, CodingKey {
        case model
        case stopReason = "stop_reason"
        case usage
    }
}

nonisolated struct UsageTokens: Codable, Sendable {
    let inputTokens: Int64
    let cacheCreationInputTokens: Int64?
    let cacheReadInputTokens: Int64?
    let outputTokens: Int64

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
    }

    /// Total tokens consumed in this turn (input + cache + output).
    var totalTokens: Int64 {
        inputTokens + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0) + outputTokens
    }

    /// The input-side token sum (input + cache_creation + cache_read), **excluding output**.
    /// These are the tokens that occupy the model's *input* context window; a model physically
    /// cannot accept more input than its window, so this is what must be compared against a
    /// context-window limit. Comparing `totalTokens` (which adds generated output on top) would
    /// let a maxed-out 200k model tip past 200k and be misclassified as a larger-window model.
    var inputSideTokens: Int64 {
        inputTokens + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
    }
}

/// One line of a Claude JSONL session log file.
nonisolated struct SessionRecord: Codable, Sendable {
    let type: String           // "assistant" or "user"
    let requestId: String?
    let sessionId: String?
    let timestamp: String
    let message: MessageContent?

    /// True when this is a complete (non-streaming) assistant record with token data.
    var isCompleteAssistantRecord: Bool {
        type == "assistant" &&
        message?.stopReason != nil &&
        (message?.usage?.outputTokens ?? 0) > 0
    }
}
