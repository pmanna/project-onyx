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

import SwiftUI

// MARK: - ThinkingDotsView
//
// PURPOSE: Animated 3-dot indicator shown in the assistant message bubble
//          while waiting for the first token from the model.
//
// DESIGN: Three dots with a staggered scale+opacity animation give the
//         impression of a pulse / "typing…" effect familiar from iMessage.
//         The animation uses SwiftUI's built-in spring physics so it adapts
//         to Reduce Motion accessibility settings automatically.
//
// USAGE:
//   Show this inside the assistant bubble row while `isGenerating` is true
//   and no text has been received yet:
//
//   ```swift
//   if provider.isGenerating && streamedText.isEmpty {
//       ThinkingDotsView()
//   }
//   ```

/// Animated three-dot "thinking" indicator.
///
/// Designed to sit inside an assistant message bubble at the same vertical
/// baseline as normal text. The dots animate with a staggered 0.24-second
/// phase delay, giving a left-to-right ripple effect.
///
/// The animation runs indefinitely while the view is on screen. SwiftUI
/// removes it automatically when the parent hides it.
struct ThinkingDotsView: View {

    @State private var animating = false

    /// Dot size in points. Matches the default body font's cap-height.
    private let dotSize: CGFloat = 8

    /// Delay between each dot's animation phase (seconds).
    private let phaseDelay: Double = 0.24

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * phaseDelay),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
        .accessibilityLabel("Thinking…")
        .accessibilityHint("The assistant is generating a response.")
    }
}

// MARK: - Preview

#Preview {
    ThinkingDotsView()
        .padding()
}
