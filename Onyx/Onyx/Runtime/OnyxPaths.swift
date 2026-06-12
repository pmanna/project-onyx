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

// MARK: - OnyxPaths
//
// PURPOSE: Single source of truth for every on-disk path the app reads or
//          writes. Using a central helper prevents path drift between the
//          downloader, registry, and model manager.
//
// PLATFORM BEHAVIOUR:
//   iOS / iPadOS  — Models live in the app sandbox's Application Support
//                   directory: <container>/Library/Application Support/Onyx/
//                   This directory is backed up by iCloud and persists across
//                   reinstalls (unlike tmp/ or Caches/).
//
//   macOS (future) — Falls back to ~/Library/Application Support/Onyx/
//                   via the same API, so the path remains consistent if you
//                   later add a macOS target.
//
// STORAGE LAYOUT:
//   <base>/Models/
//   ├── active.txt                    ← single line: active HF model id
//   ├── mlx-community/
//   │   └── Qwen2.5-3B-Instruct-4bit/
//   │       ├── config.json
//   │       ├── *.safetensors
//   │       └── tokenizer files
//   └── .cache/
//       ├── models/<org>/<name>/      ← HubApi resumable cache
//       └── download-log.txt          ← timestamped download diagnostics

/// Sandbox-safe filesystem paths for Onyx's model store.
///
/// Use these helpers everywhere instead of hard-coding paths so the app works
/// correctly on iOS (sandboxed container) and macOS (home directory).
enum OnyxPaths {

    // MARK: - Base directory

    /// The app's writable root: `<AppSupport>/Onyx/`.
    ///
    /// On iOS this resolves to the sandbox container's Application Support
    /// directory, which is the correct place for user-generated data that
    /// should persist across app updates. On macOS it maps to
    /// `~/Library/Application Support/Onyx/`.
    nonisolated static func baseDirectory() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)
        return appSupport.appendingPathComponent("Onyx", isDirectory: true)
    }

    // MARK: - Models directory

    /// Root of the model store: `<base>/Models/`.
    ///
    /// Each installed model occupies a subdirectory keyed by its HuggingFace
    /// repo id, e.g. `<base>/Models/mlx-community/Qwen2.5-3B-Instruct-4bit/`.
    nonisolated static func modelsDirectory() -> URL {
        baseDirectory().appendingPathComponent("Models", isDirectory: true)
    }

    /// On-disk directory for a specific model id.
    ///
    /// - Parameter modelId: HuggingFace model id, e.g.
    ///   `"mlx-community/Qwen2.5-3B-Instruct-4bit"`.
    /// - Returns: The expected install path. The directory may or may not
    ///   exist — use `ChatModelRegistry.isInstalled(_:)` to check.
    nonisolated static func modelDirectory(for modelId: String) -> URL {
        modelsDirectory().appendingPathComponent(modelId, isDirectory: true)
    }

    // MARK: - Pointer file

    /// Flat text file recording which model is currently active.
    ///
    /// Content: a single line containing the HF model id, no trailing
    /// newline. Written atomically by `ChatModelRegistry.setActive(_:)`.
    nonisolated static func activeModelFile() -> URL {
        modelsDirectory().appendingPathComponent("active.txt", isDirectory: false)
    }

    // MARK: - Download cache

    /// HubApi's resumable download cache: `<base>/Models/.cache/`.
    ///
    /// Keeping the cache inside the models directory means HubApi can use
    /// hard links when materialising downloads — the snapshot and the
    /// installed copy share inode blocks, costing ~0 extra disk space on
    /// the same APFS volume.
    nonisolated static func downloadCacheDirectory() -> URL {
        modelsDirectory().appendingPathComponent(".cache", isDirectory: true)
    }

    /// Plain-text download audit log: one timestamped line per event.
    ///
    /// Useful for diagnosing failed downloads: open the Files app →
    /// On My iPhone → Onyx → Models/.cache/download-log.txt, or
    /// stream it in Xcode's device console via the os.log mirror in
    /// `ChatModelDownloader`.
    nonisolated static func downloadLogFile() -> URL {
        downloadCacheDirectory().appendingPathComponent("download-log.txt")
    }
}
