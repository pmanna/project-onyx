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
import Hub
import os.log

// MARK: - ChatModelDownloader
//
// PURPOSE: Downloads MLX models from HuggingFace and installs them into the
//          local model store (`OnyxPaths.modelDirectory(for:)`).
//
// CONCURRENCY MODEL:
//   Only one download may be in-flight at a time (models are 1–4 GB each
//   and iPhone storage is limited). Attempting to start a second download
//   throws `.busy`.
//
//   UI can subscribe to live progress via `subscribe(id:)` which returns an
//   `AsyncStream<State>`. Subscribing is decoupled from downloading: tearing
//   down a subscriber (e.g. the user swipes away the Models tab) does NOT
//   cancel the download. Only `cancel(_:)` stops a download.
//
// FIVE-PHASE PIPELINE:
//   1. resolving  — HEAD-check repo exists on HF (catches typos and gated repos early)
//   2. preparing  — validate disk space (1.1× headroom), create directories
//   3. downloading — HubApi.snapshot with exponential-backoff retry
//   4. verifying  — validate config.json + weight file sizes
//   5. done / failed / cancelled
//
// RESUMPTION:
//   HubApi caches partial downloads under `OnyxPaths.downloadCacheDirectory()`.
//   If the app is killed mid-download, restarting it and tapping Download again
//   will resume from where HubApi left off.

/// Downloads HuggingFace MLX models with progress reporting.
///
/// ## Usage — start a download
/// ```swift
/// let descriptor = ChatModelCatalog.all[0]
/// try await ChatModelDownloader.shared.start(
///     modelId: descriptor.id,
///     matching: descriptor.filePatterns,
///     installPath: OnyxPaths.modelDirectory(for: descriptor.id),
///     approxSizeBytes: descriptor.approxSizeBytes
/// )
/// ```
///
/// ## Usage — observe progress
/// ```swift
/// for await state in await ChatModelDownloader.shared.subscribe(id: descriptor.id) ?? AsyncStream.empty {
///     updateProgressBar(downloaded: state.bytesDownloaded, total: state.bytesTotal)
///     if state.isTerminal { break }
/// }
/// ```
public actor ChatModelDownloader {

    /// Shared singleton.
    public static let shared = ChatModelDownloader()

    /// os.log stream. Filter on subsystem `ai.chatmlx.download` in Console.app.
    nonisolated static let osLog = Logger(subsystem: "ai.chatmlx.download", category: "ChatModelDownloader")

    // MARK: - State surface

    /// Phase within the download pipeline.
    public enum Phase: String, Sendable, Codable {
        /// Checking the repo exists on HuggingFace (cheap HEAD-equivalent).
        case resolving
        /// Creating directories, validating free disk space.
        case preparing
        /// Streaming bytes from HuggingFace.
        case downloading
        /// Hard-linking into the install path and verifying weights.
        case verifying
        /// Download completed successfully.
        case done
        /// Download failed. See `State.error` for the user-readable reason.
        case failed
        /// Download was cancelled by the user.
        case cancelled
    }

    /// A snapshot of download progress for one model.
    public struct State: Sendable, Equatable {
        public let id: String
        public let phase: Phase
        public let bytesDownloaded: Int64
        public let bytesTotal: Int64
        /// Non-nil when `phase == .failed`.
        public let error: String?

        public init(id: String, phase: Phase, bytesDownloaded: Int64,
                    bytesTotal: Int64, error: String? = nil) {
            self.id = id; self.phase = phase
            self.bytesDownloaded = bytesDownloaded; self.bytesTotal = bytesTotal
            self.error = error
        }

        /// `true` for `.done`, `.failed`, `.cancelled` — no further updates expected.
        public var isTerminal: Bool {
            phase == .done || phase == .failed || phase == .cancelled
        }

        /// Download progress 0.0–1.0, or nil before the total is known.
        public var fraction: Double? {
            guard bytesTotal > 0 else { return nil }
            return min(1.0, Double(bytesDownloaded) / Double(bytesTotal))
        }

        /// Whole-pipeline progress 0.0–1.0 for a single progress bar.
        /// Every phase advances the bar: resolving 3%, preparing 8%,
        /// downloading 10–95%, verifying 97%, done 100%.
        public var overallFraction: Double {
            switch phase {
            case .resolving:   return 0.03
            case .preparing:   return 0.08
            case .downloading: return 0.10 + 0.85 * (fraction ?? 0)
            case .verifying:   return 0.97
            case .done:        return 1.0
            case .failed, .cancelled:
                return 0.10 + 0.85 * (fraction ?? 0)
            }
        }
    }

    // MARK: - Download errors

    /// Typed errors for every failure mode in the download pipeline.
    ///
    /// Each case carries a user-friendly `errorDescription` that you can
    /// surface directly in the UI without additional mapping.
    public enum DownloaderError: Error, LocalizedError {
        case busy(other: String)
        case missingConfig
        case weightsTooSmall(bytes: Int)
        case repoNotFound(id: String)
        case repoAuthRequired(id: String)
        case rateLimited
        case networkUnavailable(String)
        case insufficientDiskSpace(needed: Int64, available: Int64)
        case repoCheckFailed(String)
        case wrappedError(String)

        public var errorDescription: String? {
            switch self {
            case .busy(let other):
                return "'\(other)' is already downloading. Cancel it or wait for it to finish."
            case .missingConfig:
                return "Downloaded files are missing config.json — the download may be incomplete. Try again."
            case .weightsTooSmall(let bytes):
                return "Weight file is only \(bytes / 1024) KB — git-lfs pointers weren't resolved. Try downloading again."
            case .repoNotFound(let id):
                return "Repo '\(id)' not found on HuggingFace. Check the model id."
            case .repoAuthRequired(let id):
                return "Repo '\(id)' is gated on HuggingFace and isn't supported by this build."
            case .rateLimited:
                return "HuggingFace is rate-limiting requests. Try again in a few minutes."
            case .networkUnavailable(let detail):
                return "Network unavailable: \(detail)"
            case .insufficientDiskSpace(let needed, let available):
                let fmt = ByteCountFormatter()
                fmt.allowedUnits = [.useGB, .useMB]; fmt.countStyle = .file
                return "Need \(fmt.string(fromByteCount: needed)) free, only \(fmt.string(fromByteCount: available)) available."
            case .repoCheckFailed(let detail):
                return "Couldn't verify repo on HuggingFace: \(detail)"
            case .wrappedError(let detail):
                return detail
            }
        }
    }

    // MARK: - Internal state

    private var activeId: String?
    private var activeTask: Task<Void, Never>?
    private var continuations: [String: [UUID: AsyncStream<State>.Continuation]] = [:]
    private var lastState: [String: State] = [:]

    // Per-download progress logging state. Lets us rate-limit progress
    // chatter to ~5% milestones + a 5-second heartbeat so a stuck download
    // still shows up in the log even when bytes aren't flowing.
    private var loggedFirstProgress: Set<String> = []
    private var lastLoggedPercent: [String: Int] = [:]
    private var lastProgressLogTime: [String: Date] = [:]
    private var lastProgressBytes: [String: Int64] = [:]

    // Highest byte count emitted so far. HubApi callbacks and the disk poller
    // interleave (and retries can re-report from zero) — the bar must never
    // move backwards.
    private var highWaterBytes: [String: Int64] = [:]

    private init() {}

    // MARK: - Query

    /// HF id of the model currently downloading, or nil if idle.
    public func activeDownloadId() -> String? { activeId }

    /// Most recently observed state for `id`. Available even after the
    /// download finishes so re-appearing UI can show the final result.
    public func lastObservedState(for id: String) -> State? { lastState[id] }

    // MARK: - Start / Cancel

    /// Start downloading `modelId`. Idempotent if `modelId` is already active.
    /// Throws `.busy` if a *different* model is downloading.
    ///
    /// Returns as soon as the download is scheduled. Subscribe via
    /// `subscribe(id:)` to observe progress.
    ///
    /// - Parameters:
    ///   - modelId: HuggingFace model id.
    ///   - revision: Git revision (default: `"main"`).
    ///   - matching: File glob patterns (use `ChatModelCatalog.defaultFilePatterns`).
    ///   - installPath: Where to materialise the model (use
    ///     `OnyxPaths.modelDirectory(for:)`).
    ///   - approxSizeBytes: Estimated download size for the progress bar.
    ///   - hfToken: Optional HuggingFace token for private/gated repos.
    public func start(
        modelId: String,
        revision: String = "main",
        matching patterns: [String],
        installPath: URL,
        approxSizeBytes: Int64
    ) throws {
        if activeId == modelId {
            Self.log(modelId: modelId, "↩️ start() ignored: already active")
            return
        }
        if let other = activeId, other != modelId {
            Self.log(modelId: modelId, "🚧 start() rejected: '\(other)' already downloading")
            throw DownloaderError.busy(other: other)
        }

        Self.log(modelId: modelId, "📥 start() invoked rev=\(revision) patterns=\(patterns.joined(separator: ",")) install=\(installPath.path)")

        activeId = modelId
        lastState[modelId] = State(id: modelId, phase: .resolving,
                                   bytesDownloaded: 0, bytesTotal: approxSizeBytes)
        loggedFirstProgress.remove(modelId)
        lastLoggedPercent[modelId] = -1
        lastProgressLogTime[modelId] = nil
        lastProgressBytes[modelId] = 0
        highWaterBytes[modelId] = 0

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.run(modelId: modelId, revision: revision,
                           patterns: patterns, installPath: installPath,
                           approxSizeBytes: approxSizeBytes)
        }
        activeTask = task
    }

    /// Cancel the in-flight download for `id`. No-op if `id` is not active.
    public func cancel(_ id: String) {
        guard activeId == id, let task = activeTask else { return }
        task.cancel()
    }

    // MARK: - Subscribe

    /// Subscribe to progress updates for `id`.
    ///
    /// Returns nil if `id` is not currently downloading. The stream
    /// immediately replays the most recent state so late subscribers don't
    /// see a blank progress bar. It finishes automatically when the download
    /// reaches a terminal phase.
    public func subscribe(id: String) -> AsyncStream<State>? {
        guard activeId == id else { return nil }
        return makeSubscriberStream(id: id)
    }

    private func makeSubscriberStream(id: String) -> AsyncStream<State> {
        AsyncStream<State> { [weak self] continuation in
            let uid = UUID()
            Task { await self?.attach(continuation: continuation, uid: uid, id: id) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.detach(uid: uid, id: id) }
            }
        }
    }

    private func attach(continuation: AsyncStream<State>.Continuation, uid: UUID, id: String) {
        if let last = lastState[id] {
            continuation.yield(last)
            if last.isTerminal {
                Self.log(modelId: id, "🔌 subscriber \(uid.uuidString.prefix(8)) attached after terminal phase \(last.phase.rawValue); finishing immediately")
                continuation.finish()
                return
            }
        }
        continuations[id, default: [:]][uid] = continuation
        let count = continuations[id]?.count ?? 0
        Self.log(modelId: id, "🔌 subscriber \(uid.uuidString.prefix(8)) attached (total=\(count))")
    }

    private func detach(uid: UUID, id: String) {
        continuations[id]?[uid] = nil
        if continuations[id]?.isEmpty == true { continuations[id] = nil }
        let count = continuations[id]?.count ?? 0
        Self.log(modelId: id, "🔌 subscriber \(uid.uuidString.prefix(8)) detached (total=\(count))")
    }

    // MARK: - Download pipeline

    private func run(
        modelId: String, revision: String, patterns: [String],
        installPath: URL, approxSizeBytes: Int64
    ) async {
        defer { activeId = nil; activeTask = nil }

        let heartbeat = Task.detached { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                tick += 1
                let state = await self?.lastState[modelId]
                let dl = state?.bytesDownloaded ?? 0
                let total = state?.bytesTotal ?? approxSizeBytes
                let phase = state?.phase.rawValue ?? "?"
                ChatModelDownloader.log(modelId: modelId,
                    "💓 heartbeat #\(tick) phase=\(phase) \(ChatModelDownloader.formatBytes(dl))/\(ChatModelDownloader.formatBytes(total))")
            }
        }
        defer { heartbeat.cancel() }

        let fmt = ByteCountFormatter(); fmt.allowedUnits = [.useGB, .useMB]; fmt.countStyle = .file
        Self.log(modelId: modelId,
            "▶️ start approxSize=\(fmt.string(fromByteCount: approxSizeBytes)) rev=\(revision) patterns=\(patterns.joined(separator: ","))")

        // Phase 1: resolve repo
        emit(State(id: modelId, phase: .resolving, bytesDownloaded: 0, bytesTotal: approxSizeBytes))
        do {
            try await Self.validateRepoExists(modelId: modelId, hfToken: nil)
            Self.log(modelId: modelId, "✅ repo resolved")
        } catch {
            let friendly = Self.friendlyError(from: error)
            Self.log(modelId: modelId, "❌ resolve failed: \(friendly.localizedDescription)")
            emit(State(id: modelId, phase: .failed, bytesDownloaded: 0,
                       bytesTotal: approxSizeBytes, error: friendly.localizedDescription))
            return
        }

        // Phase 2: disk space + directory prep
        let cacheRoot = OnyxPaths.downloadCacheDirectory()
        Self.log(modelId: modelId, "📂 cacheRoot=\(cacheRoot.path) installPath=\(installPath.path)")
        emit(State(id: modelId, phase: .preparing, bytesDownloaded: 0, bytesTotal: approxSizeBytes))
        do {
            try Self.ensureDiskSpace(neededBytes: approxSizeBytes, near: cacheRoot)
            try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: installPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            Self.log(modelId: modelId, "✅ prep ok")
        } catch {
            let friendly = Self.friendlyError(from: error)
            Self.log(modelId: modelId, "❌ prep failed: \(friendly.localizedDescription)")
            emit(State(id: modelId, phase: .failed, bytesDownloaded: 0,
                       bytesTotal: approxSizeBytes, error: friendly.localizedDescription))
            return
        }

        // Phase 3: download via HubApi (with retry)
        emit(State(id: modelId, phase: .downloading, bytesDownloaded: 0, bytesTotal: approxSizeBytes))
        let client = HubApi(downloadBase: cacheRoot)

        // HubApi's progress callbacks can go silent for 60–90 s while bytes
        // stream to disk (observed in real runs). Poll the cache + tmp
        // directories every second and surface real byte growth so the
        // progress bar keeps moving. emitProgress takes the max of both
        // sources, so the interleaving is safe.
        let diskBaseline = Self.bytesOnDisk(cacheRoot: cacheRoot)
        let diskPoller = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                let grown = ChatModelDownloader.bytesOnDisk(cacheRoot: cacheRoot) - diskBaseline
                guard grown > 0 else { continue }
                await self?.emitProgress(modelId: modelId, downloaded: grown, total: approxSizeBytes)
            }
        }
        defer { diskPoller.cancel() }

        let snapshotURL: URL
        do {
            snapshotURL = try await Self.snapshotWithRetry(
                client: client, modelId: modelId, revision: revision,
                patterns: patterns, approxSizeBytes: approxSizeBytes,
                onProgress: { [weak self] dl, total in
                    guard let self else { return }
                    Task { await self.emitProgress(modelId: modelId, downloaded: dl, total: total) }
                }
            )
            Self.log(modelId: modelId, "✅ snapshot ok")
            diskPoller.cancel()
        } catch is CancellationError {
            Self.log(modelId: modelId, "🚫 cancelled")
            emit(State(id: modelId, phase: .cancelled, bytesDownloaded: 0, bytesTotal: approxSizeBytes))
            return
        } catch {
            let friendly = Self.friendlyError(from: error)
            Self.log(modelId: modelId, "❌ download failed: \(friendly.localizedDescription)")
            emit(State(id: modelId, phase: .failed, bytesDownloaded: 0,
                       bytesTotal: approxSizeBytes, error: friendly.localizedDescription))
            return
        }

        // Phase 4: verify + link into user-visible path
        emit(State(id: modelId, phase: .verifying,
                   bytesDownloaded: approxSizeBytes, bytesTotal: approxSizeBytes))
        do {
            try linkSnapshotIntoInstallPath(snapshot: snapshotURL, installPath: installPath, modelId: modelId)
            try verifyInstall(installPath, modelId: modelId)
            Self.log(modelId: modelId, "✅ verified")
        } catch {
            try? FileManager.default.removeItem(at: installPath)
            let friendly = Self.friendlyError(from: error)
            Self.log(modelId: modelId, "❌ verify failed: \(friendly.localizedDescription)")
            emit(State(id: modelId, phase: .failed, bytesDownloaded: approxSizeBytes,
                       bytesTotal: approxSizeBytes, error: friendly.localizedDescription))
            return
        }

        Self.log(modelId: modelId, "🎉 done")
        emit(State(id: modelId, phase: .done,
                   bytesDownloaded: approxSizeBytes, bytesTotal: approxSizeBytes))
    }

    // MARK: - Pre-flight: repo existence

    /// `GET /api/models/<id>` with optional bearer auth. Throws a typed
    /// `DownloaderError` for 4xx/429 so the UI shows a specific message
    /// rather than a generic network error.
    public static func validateRepoExists(
        modelId: String, hfToken: String?,
        urlSession: URLSession = .shared
    ) async throws {
        guard let url = URL(string: "https://huggingface.co/api/models/\(modelId)") else {
            throw DownloaderError.repoCheckFailed("malformed model id")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"; req.timeoutInterval = 10
        let auth = hfToken != nil ? "Bearer ***" : "none"
        log(modelId: modelId, "🔍 resolve GET \(url.absoluteString) auth=\(auth)")
        if let token = hfToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, response): (Data, URLResponse)
        do { (_, response) = try await urlSession.data(for: req) }
        catch {
            log(modelId: modelId, "🔍 resolve network error: \(error.localizedDescription)")
            throw friendlyError(from: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DownloaderError.repoCheckFailed("non-HTTP response")
        }
        log(modelId: modelId, "🔍 resolve HTTP \(http.statusCode)")
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw DownloaderError.repoAuthRequired(id: modelId)
        case 404: throw DownloaderError.repoNotFound(id: modelId)
        case 429: throw DownloaderError.rateLimited
        default: throw DownloaderError.repoCheckFailed("HTTP \(http.statusCode)")
        }
    }

    // MARK: - Pre-flight: disk space

    /// Throws `.insufficientDiskSpace` if less than 1.1× `neededBytes` is free.
    public static func ensureDiskSpace(neededBytes: Int64, near path: URL) throws {
        let fm = FileManager.default
        let probe = fm.fileExists(atPath: path.path) ? path.path : NSHomeDirectory()
        let attrs = try fm.attributesOfFileSystem(forPath: probe)
        let free = (attrs[.systemFreeSize] as? Int64)
            ?? (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let required = neededBytes + neededBytes / 10  // 1.1× headroom (install uses hard links, not copies)
        let fmt = ByteCountFormatter(); fmt.allowedUnits = [.useGB, .useMB]; fmt.countStyle = .file
        log(modelId: "<diskcheck>",
            "💾 free=\(fmt.string(fromByteCount: free)) required=\(fmt.string(fromByteCount: required)) model=\(fmt.string(fromByteCount: neededBytes)) probe=\(probe)")
        if free < required {
            throw DownloaderError.insufficientDiskSpace(needed: required, available: free)
        }
    }

    // MARK: - Retry-with-backoff

    /// Up to 3 attempts with 1s → 3s → 9s backoff. 4xx and cancellation
    /// are not retried — they won't succeed on retry.
    nonisolated private static func snapshotWithRetry(
        client: HubApi, modelId: String, revision: String, patterns: [String],
        approxSizeBytes: Int64, onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let backoffs: [UInt64] = [1_000_000_000, 3_000_000_000, 9_000_000_000]
        var lastError: Error?
        for attempt in 0...backoffs.count {
            try Task.checkCancellation()
            let started = Date()
            log(modelId: modelId, "🚚 HubApi.snapshot attempt \(attempt + 1) starting (rev=\(revision))")
            do {
                let url = try await client.snapshot(
                    from: modelId, revision: revision, matching: patterns,
                    progressHandler: { progress in
                        let units = progress.totalUnitCount
                        if units > 10_000 {
                            // HubApi reporting actual bytes
                            onProgress(Int64(progress.completedUnitCount), Int64(units))
                        } else if units > 0 {
                            // HubApi reporting file count — scale to approx bytes
                            let fraction = Double(progress.completedUnitCount) / Double(units)
                            onProgress(Int64(fraction * Double(approxSizeBytes)), approxSizeBytes)
                        } else {
                            onProgress(0, approxSizeBytes)
                        }
                    }
                )
                let elapsed = Date().timeIntervalSince(started)
                log(modelId: modelId, "🚚 HubApi.snapshot returned in \(String(format: "%.1f", elapsed))s → \(url.path)")
                return url
            } catch is CancellationError {
                log(modelId: modelId, "🚫 HubApi.snapshot cancelled after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
                throw CancellationError()
            } catch {
                lastError = error
                let elapsed = Date().timeIntervalSince(started)
                log(modelId: modelId, "⚠️ attempt \(attempt + 1) failed after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription)")
                guard isTransient(error), attempt < backoffs.count else {
                    log(modelId: modelId, "⛔️ giving up: transient=\(isTransient(error)) attempt=\(attempt + 1)/\(backoffs.count + 1)")
                    break
                }
                let backoffSec = Double(backoffs[attempt]) / 1_000_000_000
                log(modelId: modelId, "⏳ backing off \(String(format: "%.0f", backoffSec))s before retry")
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
        }
        throw lastError ?? DownloaderError.wrappedError("unknown snapshot failure")
    }

    /// Returns true for errors worth retrying (timeouts, drops, 5xx).
    public static func isTransient(_ error: Error) -> Bool {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .badServerResponse: return true
            default: return false
            }
        }
        let lower = error.localizedDescription.lowercased()
        return lower.contains("timed out") || lower.contains("connection") || lower.contains("temporarily")
    }

    // MARK: - Error translation

    /// Map any thrown error to a user-friendly `DownloaderError`.
    public static func friendlyError(from error: Error) -> DownloaderError {
        if let dl = error as? DownloaderError { return dl }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet: return .networkUnavailable("No internet connection")
            case .timedOut: return .networkUnavailable("Request timed out")
            case .cannotConnectToHost: return .networkUnavailable("Can't reach HuggingFace")
            case .networkConnectionLost: return .networkUnavailable("Connection dropped mid-transfer")
            default: return .networkUnavailable(url.localizedDescription)
            }
        }
        return .wrappedError(error.localizedDescription)
    }

    // MARK: - Install path materialisation

    /// Hard-link each file from `snapshot` into `installPath`. Uses copy as
    /// a fallback for cross-volume scenarios (e.g. external drives).
    private func linkSnapshotIntoInstallPath(snapshot: URL, installPath: URL, modelId: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: installPath, withIntermediateDirectories: true)
        let resolved = snapshot.resolvingSymlinksInPath()
        let entries = try fm.contentsOfDirectory(
            at: resolved, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles])
        Self.log(modelId: modelId, "🔗 linking \(entries.count) entries from \(resolved.path) → \(installPath.path)")
        var linked = 0; var copied = 0
        for entry in entries {
            let dest = installPath.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            let src = entry.resolvingSymlinksInPath()
            do {
                try fm.linkItem(at: src, to: dest)
                linked += 1
            } catch {
                Self.log(modelId: modelId, "⚠️ link failed for \(entry.lastPathComponent) (\(error.localizedDescription)), falling back to copy")
                try fm.copyItem(at: src, to: dest)
                copied += 1
            }
        }
        Self.log(modelId: modelId, "🔗 install complete: \(linked) linked, \(copied) copied")
    }

    /// Verify `config.json` exists and the largest `.safetensors` file is
    /// at least 100 MB (guards against git-lfs pointer files).
    private func verifyInstall(_ root: URL, modelId: String) throws {
        let fm = FileManager.default
        let hasConfig = fm.fileExists(atPath: root.appendingPathComponent("config.json").path)
        let hasIndex  = fm.fileExists(atPath: root.appendingPathComponent("model_index.json").path)
        Self.log(modelId: modelId, "🔎 verify config.json=\(hasConfig) model_index.json=\(hasIndex)")
        guard hasConfig || hasIndex else { throw DownloaderError.missingConfig }

        var largestSize = 0
        var weightCount = 0
        var totalWeightBytes = 0
        if let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) {
            for case let entry as URL in enumerator {
                guard entry.pathExtension == "safetensors" else { continue }
                let v = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard v?.isRegularFile == true, let size = v?.fileSize else { continue }
                weightCount += 1
                totalWeightBytes += size
                if size > largestSize { largestSize = size }
            }
        }
        let fmt = ByteCountFormatter(); fmt.allowedUnits = [.useGB, .useMB]; fmt.countStyle = .file
        Self.log(modelId: modelId,
            "🔎 verify weights=\(weightCount) totalSize=\(fmt.string(fromByteCount: Int64(totalWeightBytes))) largestShard=\(fmt.string(fromByteCount: Int64(largestSize)))")
        if largestSize > 0 && largestSize < 100 * 1024 * 1024 {
            throw DownloaderError.weightsTooSmall(bytes: largestSize)
        }
    }

    // MARK: - Emission helpers

    private func emit(_ state: State) {
        lastState[state.id] = state
        let subs = continuations[state.id] ?? [:]
        for (_, c) in subs { c.yield(state) }
        if state.isTerminal {
            for (_, c) in subs { c.finish() }
            continuations[state.id] = nil
        }
    }

    private func emitProgress(modelId: String, downloaded rawDownloaded: Int64, total: Int64) {
        let phase = lastState[modelId]?.phase ?? .downloading
        // Only the downloading phase takes byte updates; a late disk-poller
        // tick must not drag a verifying/terminal state backwards.
        guard phase == .downloading else { return }

        // Monotonic: never report fewer bytes than already shown.
        let downloaded = max(rawDownloaded, highWaterBytes[modelId] ?? 0)
        highWaterBytes[modelId] = downloaded

        let effectiveTotal = max(total, downloaded)
        let next = State(id: modelId, phase: phase,
                         bytesDownloaded: downloaded, bytesTotal: effectiveTotal)
        lastState[modelId] = next
        for (_, c) in continuations[modelId] ?? [:] { c.yield(next) }

        // First progress callback — tells us bytes actually started flowing.
        if !loggedFirstProgress.contains(modelId) {
            loggedFirstProgress.insert(modelId)
            let totalLabel = total > 0 ? Self.formatBytes(total) : "unknown"
            Self.log(modelId: modelId, "📦 first progress callback dl=\(Self.formatBytes(downloaded)) total=\(totalLabel)")
        }

        // 5% milestone logging.
        if effectiveTotal > 0 {
            let pct = Int(Double(downloaded) / Double(effectiveTotal) * 100.0)
            let last = lastLoggedPercent[modelId] ?? -1
            if pct >= last + 5 {
                lastLoggedPercent[modelId] = pct
                Self.log(modelId: modelId, "📦 \(pct)% dl=\(Self.formatBytes(downloaded))/\(Self.formatBytes(effectiveTotal))")
            }
        }

        // Heartbeat: every 5s, log throughput. Lets us spot a stalled download
        // (no bytes flowing) even when % is constant.
        let now = Date()
        if let lastTime = lastProgressLogTime[modelId] {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= 5.0 {
                let lastBytes = lastProgressBytes[modelId] ?? 0
                let delta = downloaded - lastBytes
                let rate = Double(delta) / elapsed
                let status = delta == 0 ? "⚠️ STALLED" : "✅ flowing"
                Self.log(modelId: modelId, "💓 heartbeat \(status) Δ=\(Self.formatBytes(delta)) over \(String(format: "%.1f", elapsed))s (≈\(Self.formatBytes(Int64(rate)))/s)")
                lastProgressLogTime[modelId] = now
                lastProgressBytes[modelId] = downloaded
            }
        } else {
            lastProgressLogTime[modelId] = now
            lastProgressBytes[modelId] = downloaded
        }
    }

    /// Total size of files under the download cache and the app's tmp
    /// directory. URLSession streams response bodies to a tmp file before
    /// HubApi moves them into the cache, so both locations are counted.
    nonisolated static func bytesOnDisk(cacheRoot: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        let roots = [cacheRoot, URL(fileURLWithPath: NSTemporaryDirectory())]
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { continue }
            for case let entry as URL in enumerator {
                let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
                total += Int64(size)
            }
        }
        return total
    }

    /// Compact byte formatter for log lines.
    nonisolated static func formatBytes(_ n: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: n)
    }

    // MARK: - Persistent log

    /// Append one ISO-8601-stamped line to the on-device download log.
    nonisolated public static func log(modelId: String, _ message: String) {
        osLog.notice("[\(modelId, privacy: .public)] \(message, privacy: .public)")
        let logURL = OnyxPaths.downloadLogFile()
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] [\(modelId)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL)
        } else if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    /// Remove all cached partial-download files while preserving the log.
    /// Exposed as a recovery action for stuck/looping downloads.
    public func clearCache() async {
        let cacheRoot = OnyxPaths.downloadCacheDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheRoot, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent != "download-log.txt" {
            try? FileManager.default.removeItem(at: entry)
        }
        Self.log(modelId: "<all>", "🧹 cleared resumable cache")
    }
}
