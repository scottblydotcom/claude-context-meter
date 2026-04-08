//
//  ModelLimits.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

enum ModelLimits {
    static let defaultContextWindow: Int64 = 200_000

    /// Returns the context window token limit for a given model name.
    static func contextWindow(for model: String) -> Int64 {
        // All current Claude models share a 200k context window.
        // This lookup exists so we can differentiate in the future.
        switch model {
        case let model where model.hasPrefix("claude-"):
            return 200_000
        default:
            return defaultContextWindow
        }
    }
}
