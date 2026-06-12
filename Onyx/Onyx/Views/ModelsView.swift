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

/// Browse, download, and manage the on-device chat model.
struct ModelsView: View {

    @State private var installedIds: Set<String> = []
    @State private var activeModelId: String? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(ChatModelCatalog.all) { descriptor in
                    DownloadRow(
                        descriptor: descriptor,
                        activeModelId: activeModelId,
                        installedIds: installedIds,
                        onActivate: activate,
                        onUninstall: uninstall
                    )
                }
            }
            .navigationTitle("Models")
            .task { await refreshState() }
        }
    }

    private func activate(_ id: String) async {
        do {
            try await ChatModelRegistry.shared.setActive(id)
            await refreshState()
        } catch {
            print("[Onyx] Activate failed: \(error.localizedDescription)")
        }
    }

    private func uninstall(_ id: String) async {
        do {
            try await ChatModelRegistry.shared.uninstall(id)
            await refreshState()
        } catch {
            print("[Onyx] Uninstall failed: \(error.localizedDescription)")
        }
    }

    private func refreshState() async {
        installedIds = await ChatModelRegistry.shared.installedIds()
        activeModelId = await ChatModelRegistry.shared.activeId()
    }
}

// MARK: - Preview

#Preview {
    ModelsView()
}
