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

// MARK: - MLXError
//
// PURPOSE: Typed error surface for the model-loading and inference layer.
//          Keeping errors in a dedicated file makes it easy to add new cases
//          (e.g. contextLengthExceeded, quantizationFailed) without touching
//          MLXModelManager.swift.
//
// USAGE:
//   do {
//       try await ChatProvider.shared.respond(to: userMessage)
//   } catch MLXError.modelNotInstalled(let id) {
//       // Guide the user to the Models tab
//   } catch MLXError.metalUnavailable {
//       // Explain that on-device inference needs Apple Silicon
//   } catch {
//       // Generic fallback
//   }

/// Errors thrown by the MLX model-loading and inference pipeline.
///
/// Every case carries a user-readable `errorDescription` so you can display
/// it directly in the UI without additional mapping.
public enum MLXError: Error, LocalizedError {

    /// A model was requested but its directory is absent under the models
    /// store. The user needs to open the Models tab and download it first.
    ///
    /// - Parameter id: The HuggingFace model id that was not found, e.g.
    ///   `"mlx-community/Qwen2.5-3B-Instruct-4bit"`.
    case modelNotInstalled(id: String)

    /// The model directory exists but `LLMModelFactory` failed to load it.
    /// Usually caused by corrupted weights, an unsupported quantisation
    /// scheme, or insufficient device RAM.
    ///
    /// - Parameter reason: Human-readable description of the failure, taken
    ///   directly from the underlying error.
    case modelLoadFailed(String)

    /// A Metal GPU is required for on-device MLX inference but
    /// `MTLCreateSystemDefaultDevice()` returned nil. This happens on
    /// iPhone simulators and very old hardware.
    ///
    /// Simulators: use a physical device to test real inference.
    case metalUnavailable

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let id):
            return "Model '\(id)' is not installed. Go to the Models tab to download it."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .metalUnavailable:
            return "Metal GPU is required for on-device inference. Run on a physical iPhone (not the simulator)."
        }
    }
}
