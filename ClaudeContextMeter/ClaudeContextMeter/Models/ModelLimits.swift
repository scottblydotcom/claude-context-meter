//
//  ModelLimits.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

/// Marked `nonisolated` because this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// without this, calls from the nonisolated ContextWindowCalculator would be Swift 6 errors.
nonisolated enum ModelLimits {
    static let defaultContextWindow: Int64 = 200_000
    static let extendedContextWindow: Int64 = 1_000_000

    /// Each model's maximum context window — the model's **input** capacity (Anthropic's Models
    /// API exposes it as `max_input_tokens`, a separate limit from `max_tokens` for output). The
    /// model's *max capability* is fixed by the model string; the *effective* window a given
    /// session is granted is not necessarily — on Claude Code the 1M window is auto-granted on
    /// Max/Team/Enterprise but requires usage credits on Pro (see the Pro limitation below).
    ///
    /// Any model **not** listed falls back to `defaultContextWindow` (200k). The upward-only
    /// safety net in `contextWindow(for:observedInputTokens:)` promotes an unlisted model to 1M
    /// once its *input-side* usage exceeds 200k — but it does **nothing** below 200k, so an
    /// unmapped 1M model used under 200k still shows the 200k denominator (the exact
    /// 178k/200k-vs-/1M under-report this fix targets). Keep this map current; the net is not a
    /// substitute for mapping a model.
    ///
    /// **Known limitation (Pro plan — tracked in claude-context-meter-n6y):** a Pro-without-
    /// credits session is genuinely capped at 200k, yet this map returns 1M for a 1M-capable
    /// model from the first record, over-stating the denominator (~5x under-report) for the
    /// **entire** session. The safety net cannot self-correct this: base is already 1M and the
    /// net only ever promotes *upward*. This is a deliberate deferral (plan-aware gating pending
    /// empirical Pro validation) — documented so the comment matches reality, not a fix.
    ///
    /// Source: platform.claude.com model catalog, checked 2026-07-24. Verify against the live
    /// catalog before editing.
    static let contextWindowByModel: [String: Int64] = [
        "claude-opus-5": extendedContextWindow,
        "claude-opus-4-6": extendedContextWindow,
        "claude-opus-4-7": extendedContextWindow,
        "claude-opus-4-8": extendedContextWindow,
        "claude-sonnet-4-6": extendedContextWindow,
        "claude-sonnet-5": extendedContextWindow,
        "claude-fable-5": extendedContextWindow,
        "claude-mythos-5": extendedContextWindow,
        "claude-haiku-4-5": defaultContextWindow
    ]

    /// The set of models this build maps to the 1M window. Derived from `contextWindowByModel`
    /// so it can't drift out of sync. Retained for tests and any caller that needs the list.
    static var extendedContextModels: Set<String> {
        Set(contextWindowByModel.filter { $0.value == extendedContextWindow }.map { $0.key })
    }

    /// Returns the context-window denominator for a session, from the model ID.
    ///
    /// `observedInputTokens` MUST be the **input-side** sum (input + cache_creation + cache_read),
    /// *excluding* output — see `UsageTokens.inputSideTokens`. The mapped window is the model's
    /// max INPUT capacity, and a model physically cannot accept more input than its window, so a
    /// genuine 200k model's input side is itself capped at 200k. (Passing `totalTokens`, which
    /// adds generated output on top, would let a maxed-out 200k model tip past 200k and be
    /// falsely promoted — that was a real bug, fixed by taking the input side here.)
    ///
    /// Safety net: if the input side exceeds the mapped window, the session must actually be
    /// running a larger window (a model we mapped low, or one not in the map), so promote to
    /// `extendedContextWindow`. Given today's **binary** 200k/1M lineup this only ever corrects
    /// under-reporting. Caveat: a hypothetical future model with a *mid-tier* window (e.g. 400k)
    /// that we failed to map would be over-promoted to 1M — revisit if the lineup stops being
    /// binary.
    static func contextWindow(for model: String, observedInputTokens: Int64) -> Int64 {
        let base = contextWindowByModel[model] ?? defaultContextWindow
        if observedInputTokens > base { return extendedContextWindow }
        return base
    }
}
