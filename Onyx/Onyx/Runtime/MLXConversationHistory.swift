// Copyright 2026 Onyx Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

// MARK: - MLXConversationHistory
//
// PURPOSE: Thread-safe turn-history buffer with automatic trimming.
//
// WHY A DEDICATED ACTOR:
//   The chat view, the chat provider, and (potentially) background tasks all
//   touch conversation history. An actor eliminates data races without manual
//   locking. Swift's structured concurrency ensures every mutation is
//   serialised through the actor's executor.
//
// CAPS AND TRIMMING:
//   On-device 3B models have a practical context window of around 4,000–8,000
//   tokens. Sending the full history of a long session would overflow the
//   context, slow generation, or cause the model to "forget" early turns.
//   Two soft caps prevent this:
//     • 16,000 characters total   (~4,000–6,000 tokens for English prose)
//     • 10 turn pairs (20 turns)  catches repetitive short messages
//   When either cap is exceeded the oldest user+assistant pair is dropped.
//
// EXTENDING THIS:
//   To add persistent history (save/restore across app launches) you can
//   encode `turns` to JSON and write to a file in OnyxPaths.baseDirectory().

/// Manages the ordered list of user and assistant turns sent to the model.
///
/// Thread-safe via Swift actor isolation. Instantiate one per chat session.
///
/// ## Usage
/// ```swift
/// let history = MLXConversationHistory()
/// await history.addUserMessage("What is the capital of France?")
/// let messages = await history.buildMessages(systemPrompt: "You are helpful.")
/// // Pass `messages` to generateFromModel(container:messages:)
/// await history.addAssistantMessage("Paris.")
/// ```
public actor MLXConversationHistory {

    // MARK: - Turn

    /// A single message in the conversation (user or assistant).
    public struct Turn: Sendable {
        public let role: String    // "user" or "assistant"
        public let content: String
    }

    // MARK: - Storage

    private var turns: [Turn] = []

    /// Soft cap: total characters across all retained turns.
    private let maxHistoryCharacters: Int

    /// Hard cap: maximum number of [user, assistant] pairs retained.
    private let maxTurnPairs: Int

    /// Default caps match the values from the reference kiraa-engine implementation.
    ///
    /// - Parameter maxHistoryCharacters: Character cap (default: 16 000).
    /// - Parameter maxTurnPairs: Turn-pair cap (default: 10 pairs = 20 messages).
    public init(maxHistoryCharacters: Int = 16_000, maxTurnPairs: Int = 10) {
        self.maxHistoryCharacters = maxHistoryCharacters
        self.maxTurnPairs = max(1, maxTurnPairs)
    }

    // MARK: - Mutations

    /// Append a user turn and trim history if needed.
    ///
    /// - Parameter content: The user's message text.
    public func addUserMessage(_ content: String) {
        turns.append(Turn(role: "user", content: content))
        trimToFit()
    }

    /// Append an assistant turn and trim history if needed.
    ///
    /// Always call this after consuming the generation stream — the
    /// [user, assistant] alternation invariant is required by most model
    /// chat templates. A missing assistant turn causes empty replies on
    /// all subsequent turns with some models (e.g. Llama).
    ///
    /// - Parameter content: The full response text (accumulate streamed
    ///   chunks before calling, or call with the partial text if cancelled).
    public func addAssistantMessage(_ content: String) {
        turns.append(Turn(role: "assistant", content: content))
        trimToFit()
    }

    /// Remove the last turn if it is an assistant reply.
    ///
    /// Used by the "regenerate" action: drop the last response so the
    /// next `buildMessages` call re-uses the same user turn. No-op if
    /// history is empty or the last turn is a user message.
    ///
    /// - Returns: `true` if an assistant turn was removed.
    @discardableResult
    public func popLastAssistant() -> Bool {
        guard turns.last?.role == "assistant" else { return false }
        turns.removeLast()
        return true
    }

    /// Clear all turns. Call when the user taps "New conversation".
    public func reset() {
        turns.removeAll()
    }

    // MARK: - Message building

    /// Build the `messages` array to pass to `generateFromModel`.
    ///
    /// The system prompt is prepended to the first user turn's content (the
    /// standard pattern for models that don't support a dedicated system
    /// role). If history is empty the returned array is empty — the caller
    /// should ensure at least one user turn exists before calling this.
    ///
    /// - Parameter systemPrompt: Instructions injected before the first user
    ///   turn. Keep this concise — every character here counts against the
    ///   16 K cap.
    /// - Returns: Array of `["role": "...", "content": "..."]` dictionaries
    ///   ready for `tokenizer.applyChatTemplate(messages:)`.
    public func buildMessages(systemPrompt: String) -> [[String: String]] {
        var result: [[String: String]] = []
        for (index, turn) in turns.enumerated() {
            if index == 0 && turn.role == "user" {
                result.append(["role": "user", "content": systemPrompt + "\n\n" + turn.content])
            } else {
                result.append(["role": turn.role, "content": turn.content])
            }
        }
        return result
    }

    // MARK: - Stats (for UI meters)

    /// Number of individual turns (user + assistant, not pairs).
    public var turnCount: Int { turns.count }

    /// Total characters across all retained turns, for the context-usage meter.
    public var totalCharacterCount: Int {
        turns.reduce(0) { $0 + $1.content.count }
    }

    /// Maximum character count this history will retain (16 000 by default).
    public static let defaultMaxCharacters: Int = 16_000

    // MARK: - Private trimming

    /// Drop the oldest [user, assistant] pair whenever either cap is exceeded.
    ///
    /// We always remove a *pair* (not a single turn) to maintain the strict
    /// user/assistant alternation required by chat templates.
    private func trimToFit() {
        var totalChars = turns.reduce(0) { $0 + $1.content.count }

        func pairCount() -> Int { turns.count / 2 }

        while (totalChars > maxHistoryCharacters || pairCount() > maxTurnPairs)
              && turns.count > 2 {
            let removed = turns.removeFirst()
            totalChars -= removed.content.count
            // Also remove the following assistant turn if it exists, to keep
            // history properly paired.
            if !turns.isEmpty && turns.first?.role == "assistant" {
                let removedAssistant = turns.removeFirst()
                totalChars -= removedAssistant.content.count
            }
        }
    }
}
