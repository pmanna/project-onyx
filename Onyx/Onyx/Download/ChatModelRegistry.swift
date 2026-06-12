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

// MARK: - ChatModelRegistry
//
// PURPOSE: Single source of truth for which models are installed on disk
//          and which one is currently active.
//
// LAYOUT:
//   <models root>/active.txt        ← single line containing the HF model id
//   <models root>/<org>/<name>/     ← model files (config.json, *.safetensors, …)
//
// INSTALLED DETECTION:
//   A model is considered installed when its directory contains `config.json`
//   (LLM-style) OR `model_index.json` (diffusers-style). We don't verify the
//   weight files here — `ChatModelDownloader.verifyInstall` handles that at
//   download time.

/// Source of truth for installed models and the active selection.
///
/// ## Usage
/// ```swift
/// // Check which models are installed
/// let installed = await ChatModelRegistry.shared.installedIds()
///
/// // Activate a model (must be installed)
/// try await ChatModelRegistry.shared.setActive("mlx-community/Qwen2.5-3B-Instruct-4bit")
///
/// // Read back the active id
/// let activeId = await ChatModelRegistry.shared.activeId()
/// ```
public actor ChatModelRegistry {

    /// Shared singleton.
    public static let shared = ChatModelRegistry()

    private var cachedActiveId: String?
    private var didLoadActiveId = false

    private init() {}

    // MARK: - Installed models

    /// Set of HuggingFace ids that are fully installed on disk.
    ///
    /// Only ids in `ChatModelCatalog.all` are scanned — stray directories
    /// the user drops into the model store are silently ignored.
    public func installedIds() -> Set<String> {
        var found = Set<String>()
        for descriptor in ChatModelCatalog.all where isInstalledOnDisk(descriptor.id) {
            found.insert(descriptor.id)
        }
        return found
    }

    /// Returns `true` if `id` is installed on disk.
    public func isInstalled(_ id: String) -> Bool {
        isInstalledOnDisk(id)
    }

    /// Check whether a model directory contains a recognisable config file.
    public nonisolated static func looksInstalled(at root: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: root.appendingPathComponent("config.json").path)
            || fm.fileExists(atPath: root.appendingPathComponent("model_index.json").path)
    }

    private nonisolated func isInstalledOnDisk(_ id: String) -> Bool {
        ChatModelRegistry.looksInstalled(at: OnyxPaths.modelDirectory(for: id))
    }

    /// Total bytes on disk for `id`. Returns 0 if the directory is missing.
    ///
    /// Shown as "2.1 GB" in the Models tab next to installed models.
    public func diskBytes(for id: String) -> Int64 {
        let root = OnyxPaths.modelDirectory(for: id)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Active model

    /// HuggingFace id of the active chat model, or nil if none is set.
    ///
    /// Returns nil if the persisted id points to a model that is no longer
    /// installed (e.g. uninstalled while the pointer file was stale).
    public func activeId() -> String? {
        if !didLoadActiveId {
            cachedActiveId = readActiveFile()
            didLoadActiveId = true
        }
        // Defensive: forget the active id if the model was uninstalled.
        if let id = cachedActiveId, !isInstalledOnDisk(id) {
            cachedActiveId = nil
            try? FileManager.default.removeItem(at: OnyxPaths.activeModelFile())
        }
        return cachedActiveId
    }

    /// Set the active model. The model must be installed on disk.
    ///
    /// Persists the selection to `active.txt` so it survives app restarts.
    ///
    /// - Throws: `RegistryError.notInstalled` if `id` is not installed.
    public func setActive(_ id: String) throws {
        guard isInstalledOnDisk(id) else {
            throw RegistryError.notInstalled(id: id)
        }
        let root = OnyxPaths.modelsDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try id.write(to: OnyxPaths.activeModelFile(), atomically: true, encoding: .utf8)
        cachedActiveId = id
        didLoadActiveId = true
    }

    /// Clear the active-model pointer.
    public func clearActive() {
        cachedActiveId = nil
        try? FileManager.default.removeItem(at: OnyxPaths.activeModelFile())
    }

    // MARK: - Uninstall

    /// Remove a model's directory from disk.
    ///
    /// If the uninstalled model was active, the active pointer is cleared.
    /// The caller is responsible for picking a new active model or showing
    /// a "no model selected" state.
    public func uninstall(_ id: String) throws {
        let root = OnyxPaths.modelDirectory(for: id)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        if cachedActiveId == id {
            cachedActiveId = nil
            try? FileManager.default.removeItem(at: OnyxPaths.activeModelFile())
        }
    }

    // MARK: - Private helpers

    private nonisolated func readActiveFile() -> String? {
        let url = OnyxPaths.activeModelFile()
        guard FileManager.default.fileExists(atPath: url.path),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Errors

    public enum RegistryError: Error, LocalizedError {
        case notInstalled(id: String)
        public var errorDescription: String? {
            switch self {
            case .notInstalled(let id):
                return "'\(id)' is not installed. Download it first."
            }
        }
    }
}
