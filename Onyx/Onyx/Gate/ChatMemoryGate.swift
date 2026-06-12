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

// MARK: - ChatMemoryGate
//
// PURPOSE: Refuse to start a model load if the device doesn't have enough
//          physical RAM to hold the model's working set resident without
//          being jetsam-killed.
//
// WHY A SEPARATE GATE:
//   `HardwareProfile.canLoadModel` contains the maths. This thin wrapper
//   looks up the model's size from the catalog, calls `canLoadModel`, and
//   throws `MLXError.modelLoadFailed` with a user-readable explanation if
//   the check fails. Keeping this logic here means `ChatProvider` stays
//   focused on inference, not RAM arithmetic.
//
// OVERRIDING IN DEVELOPMENT:
//   Set the `CHATM_HARDWARE_TIER=pro` environment variable in the Xcode
//   scheme to bypass the gate. This is useful when testing on a device
//   with slightly less RAM than the model requires.

/// Pre-flight memory check before loading an MLX model.
///
/// Throws `MLXError.modelLoadFailed` if the device lacks sufficient RAM to
/// safely run the requested model. Unknown model ids (not in the catalog)
/// are allowed through — the registry only activates catalog models, and
/// blocking an unknown id would be worse than attempting the load.
enum ChatMemoryGate {

    /// Assert that the device can load `modelId` without OOM risk.
    ///
    /// - Parameter modelId: HuggingFace model id to check.
    /// - Throws: `MLXError.modelLoadFailed` with a human-readable description
    ///   if the device's physical RAM is insufficient.
    static func assertCanLoad(modelId: String) throws {
        // Unknown ids (not in catalog) pass through — we'd rather attempt
        // the load than block it on a missing size estimate.
        guard let descriptor = ChatModelCatalog.descriptor(forId: modelId) else { return }

        let profile = HardwareProfile.default
        guard profile.canLoadModel(approxSizeBytes: descriptor.approxSizeBytes) else {
            let needGB = Double(descriptor.approxSizeBytes) / 1_073_741_824.0
                + Double(HardwareProfile.defaultModelHeadroomMB) / 1_024.0
            throw MLXError.modelLoadFailed(
                String(format:
                    "Not enough RAM for %@: needs ≈ %.1f GB but this device has %d GB. " +
                    "Try a smaller model, or set CHATM_HARDWARE_TIER=pro in the Xcode scheme.",
                    descriptor.displayName, needGB, profile.detectedRAMGigabytes
                )
            )
        }
    }
}
