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

/// @MainActor singleton that manages user preferences.
@MainActor
@Observable
public final class OnyxSettings {

    public static let shared = OnyxSettings()

    private static let logPromptsKey = "onyx.logPrompts"

    public var logPrompts: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.logPromptsKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.logPromptsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.logPromptsKey)
        }
    }

    private init() {}
}
