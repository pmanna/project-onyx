# Onyx — Developer Quickstart

Get from a fresh Mac to a working on-device LLM chat app in under 30 minutes.

> **Physical iPhone required.** The iOS Simulator has no Metal GPU and cannot run inference. You need an iPhone 15 or later with at least 6 GB of RAM.

> ⚠️ **iOS 17–26 required. iOS 27 beta is not yet supported** — the app crashes at launch on the iOS 27 beta (under investigation).

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Install Xcode](#2-install-xcode)
3. [Create a free Apple Developer account](#3-create-a-free-apple-developer-account)
4. [Clone and open the project](#4-clone-and-open-the-project)
5. [Configure signing](#5-configure-signing)
6. [Enable Developer Mode on your iPhone](#6-enable-developer-mode-on-your-iphone)
7. [Connect your iPhone](#7-connect-your-iphone)
8. [Build and run](#8-build-and-run)
9. [Download your first model](#9-download-your-first-model)
10. [Start chatting](#10-start-chatting)
11. [First things to customise](#11-first-things-to-customise)
12. [What's next](#12-whats-next)
13. [Troubleshooting](#13-troubleshooting)
14. [Learning resources](#14-learning-resources)

---

## 1. Prerequisites

Before you start, make sure you have:

| Requirement | Minimum version | Notes |
|---|---|---|
| Mac | macOS 14 Sonoma | Needed to run Xcode 16 |
| Xcode | 16.0 | Free from the App Store |
| Apple ID | Any | A paid developer account is **not** required to run on your own device |
| iPhone | iPhone 15 (any model) | 6 GB RAM minimum; physical device only |
| iOS | 17.0 – 26.x | **iOS 27 beta is not supported** (app crashes at launch) |
| Cable | USB-A to Lightning **or** USB-C to USB-C | For the initial trust handshake; wireless debugging works afterward |
| Wi-Fi | 2.4 GHz or 5 GHz | For downloading the ≈ 860 MB model file |
| Disk space | ≈ 2 GB free on iPhone | The model + app + system headroom |

---

## 2. Install Xcode

Xcode is Apple's free IDE for iOS development. It bundles the Swift compiler, Simulator, Instruments, and the toolchain for signing and deploying to devices.

1. Open the **App Store** on your Mac and search for **Xcode**, or visit [developer.apple.com/xcode](https://developer.apple.com/xcode/).
2. Click **Get** (it's free, but large — around 15 GB).
3. After installation, launch Xcode once. It will install additional components. This takes a few minutes.
4. Accept the Xcode license agreement when prompted (or run `sudo xcodebuild -license accept` in Terminal).

> **Command-line tools:** If you plan to use the `xcodebuild` CLI, also run:
> ```bash
> xcode-select --install
> ```

---

## 3. Create a free Apple Developer account

You need an Apple ID linked to Apple's developer portal to sign and install apps on your own device. A **free** personal team is sufficient — you do not need the paid $99/year Apple Developer Program to run on a single device you own.

1. Open [developer.apple.com](https://developer.apple.com/) and sign in with your Apple ID.
2. Agree to the Apple Developer Agreement if prompted.
3. That's it. Xcode will pick up your account automatically.

**Paid program vs free account:**

| | Free | Paid ($99/year) |
|---|---|---|
| Run on your own device | ✓ | ✓ |
| Distribute on App Store | ✗ | ✓ |
| Push notifications (production) | ✗ | ✓ |
| App validity before re-signing | 7 days | 1 year |

For development and forking Onyx, the free account is all you need.

→ Learn more: [Apple Developer Program](https://developer.apple.com/programs/)

---

## 4. Clone and open the project

```bash
git clone https://github.com/your-org/Onyx.git
cd Onyx
open Onyx/Onyx.xcodeproj
```

Xcode opens the project. The first time, it automatically resolves the Swift package dependencies (`mlx-swift-lm` and `swift-transformers`). This can take 1–3 minutes on a fast connection.

You'll see a progress spinner in the bottom status bar — wait for it to finish before trying to build.

> **What are Swift packages?** They're Xcode's native dependency manager (similar to npm or CocoaPods). The packages are declared in `Package.swift` and fetched from GitHub automatically.  
> → Learn more: [Adding Package Dependencies to Your App](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)

---

## 5. Configure signing

iOS apps must be cryptographically signed before they can run on a device. Xcode handles this for you — you just need to set your team.

1. In the Xcode Project Navigator (left sidebar), click the **Onyx** project file (the blue icon at the top).
2. Select the **Onyx** target under **TARGETS**.
3. Click the **Signing & Capabilities** tab.
4. Under **Team**, open the dropdown and select your Apple ID / personal team.
5. Xcode will auto-generate a provisioning profile. If it shows a red error about the bundle ID being taken, change the **Bundle Identifier** from `kiraa.Onyx` to something unique — e.g. `com.yourname.Onyx`.

Once the team is set and the bundle ID is unique, the signing error disappears.

> **What is code signing?** Apple requires every app to be signed by an identity tied to a developer account. This prevents tampering and lets Apple track which developer built what. Xcode manages certificates and provisioning profiles for you.  
> → Learn more: [Code Signing Guide](https://developer.apple.com/documentation/xcode/distribution-overview)

---

## 6. Enable Developer Mode on your iPhone

iOS 16 and later requires you to opt in to Developer Mode before Xcode can install apps on your device. You only do this once per device.

1. On your iPhone, open **Settings → Privacy & Security**.
2. Scroll to the bottom and tap **Developer Mode**.
3. Toggle it **on**.
4. Tap **Restart** when prompted.
5. After restart, a banner appears — tap **Turn On** and enter your passcode.

Developer Mode stays enabled until you manually turn it off or restore the device.

→ Learn more: [Enabling Developer Mode on a Device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

---

## 7. Connect your iPhone

### First-time connection (USB)

1. Plug your iPhone into your Mac using a Lightning or USB-C cable.
2. On your iPhone, tap **Trust** when the "Trust This Computer?" prompt appears, then enter your passcode.
3. Your iPhone appears in Xcode's device list (top-left scheme picker).

### Switch to wireless (optional but convenient)

After the initial USB trust, you can deploy wirelessly:

1. In Xcode, go to **Window → Devices and Simulators**.
2. Select your iPhone and tick **Connect via Network**.
3. Unplug the cable. Your device now shows a globe icon — wireless debugging is active.

Wireless requires the Mac and iPhone to be on the same Wi-Fi network. Build times are slightly slower wirelessly, but it's handy for running the app while the phone is away from the desk.

→ Learn more: [Running Your App in Simulator or on a Device](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device)

---

## 8. Build and run

1. In the Xcode scheme picker (top-left toolbar), make sure your iPhone is selected — **not** a Simulator.
2. Press **⌘R** (or **Product → Run**).
3. Xcode compiles the Swift sources, links the MLX frameworks, and installs the app on your device.

First build takes 2–5 minutes because Xcode compiles the MLX Swift packages from source. Subsequent builds are incremental and much faster.

**If you see "Untrusted Developer" on your iPhone:**  
Go to **Settings → General → VPN & Device Management**, tap your developer account, and tap **Trust**.

Once the app launches, you'll land directly on the Chat tab.

---

## 9. Download your first model

Onyx ships with one pre-configured model: **Llama 3.2 1B Instruct (4-bit)**. The weights aren't bundled in the app — you download them once, publicly, with no HuggingFace account or token.

1. Tap the **Models** tab (bottom navigation bar, stack icon).
2. Find **Llama 3.2 1B Instruct (4-bit)** — marked "Recommended".
3. Tap **Download**. The download is ≈ 860 MB — connect to Wi-Fi.
4. The progress bar starts moving immediately and shows live percentage.
5. When the download completes, the model **activates automatically** — no extra tap needed.

> **Where does the model go?** It's stored at `<AppSupport>/Onyx/Models/mlx-community/Llama-3.2-1B-Instruct-4bit/` inside the app's sandbox. You can browse it in the **Files** app → On My iPhone → Onyx.

> **What is 4-bit quantisation?** The original model weights are stored in float32 or bfloat16. Quantisation compresses them to 4 bits per weight, shrinking a multi-GB model to a fraction of its size with a modest quality trade-off. This is what makes LLMs fit in 6 GB of iPhone RAM.  
> → Learn more: [mlx-community on HuggingFace](https://huggingface.co/mlx-community) — the community that maintains these quantised models.

---

## 10. Start chatting

1. Tap the **Chat** tab.
2. You'll see the model name in the navigation bar title area, with a green status dot indicating the model is loaded (or will load on first message).
3. Type a message in the text field and tap the send button (or press Return).
4. The three-dot thinking indicator appears while the model loads on the first turn (5–15 seconds on iPhone 15).
5. Tokens stream in real time as the model generates its response.

**Token speed:** Expect 15–35 tokens/second on iPhone 15 base, and 30–50+ tokens/second on iPhone 15 Pro / iPhone 16 Pro with A18 Pro.

> **What is token streaming?** Instead of waiting for the full response, the app receives one token (roughly one word or word-fragment) at a time via an `AsyncStream<String>`. The UI appends each token to the message bubble as it arrives, giving the typewriter effect.  
> → Learn more: [AsyncStream](https://developer.apple.com/documentation/swift/asyncstream)

---

## 11. First things to customise

### Open Settings

Tap the **Settings** tab (bottom navigation bar, gear icon). It has two sections:

| Section | What you can change |
|---|---|
| **Assistant** | System prompt — injected before every conversation |
| **Developer** | Clear incomplete download cache |

Changes save when you leave the tab. The system prompt takes effect on the next message.

### Change the system prompt in code

```swift
ChatProvider.shared.systemPrompt = "You are a senior Swift engineer. Answer only in Swift code."
```

### Watch the inference log

Every outgoing prompt is logged to the Xcode console by default. Look for:

```
📨 [Onyx] outgoing prompt — 2026-06-12T...
```

To disable in code:

```swift
OnyxSettings.shared.logPrompts = false
```

### Force a hardware tier (for testing)

To simulate a different hardware tier without changing devices, set an environment variable in your Xcode scheme:

1. **Product → Scheme → Edit Scheme** (⌘<)
2. Select **Run → Arguments → Environment Variables**
3. Add `CHATM_HARDWARE_TIER` = `pro` (or `base` / `max` / `ultra`)

This lets you test the memory gate behaviour on a device with more RAM than your smallest target.

---

## 12. What's next

### Add a model (1 line of code)

Open [ChatModelCatalog.swift](Onyx/Onyx/Download/ChatModelCatalog.swift) and append to `ChatModelCatalog.all`:

```swift
ChatModelDescriptor(
    id: "mlx-community/gemma-2-2b-it-4bit",
    displayName: "Gemma 2 2B Instruct (4-bit)",
    family: .other,
    approxSizeBytes: Int64(1.5 * 1_073_741_824),  // ≈ 1.5 GB
    filePatterns: ChatModelCatalog.defaultFilePatterns,
    summary: "Google's compact 2B instruction-tuned model."
)
```

Rebuild and the model appears in the Models tab automatically.

Browse available models at [huggingface.co/mlx-community](https://huggingface.co/mlx-community) — filter by "4bit" for iPhone-compatible sizes.

### Add conversation persistence

Conversations reset on restart by design (keeps the skeleton simple). To save and restore them:

```swift
// Save — call after each assistant message:
let turns = await ChatProvider.shared.history.turns
let data = try JSONEncoder().encode(turns)
try data.write(to: OnyxPaths.baseDirectory().appending(path: "history.json"))

// Restore — call at app launch:
let saved = try Data(contentsOf: OnyxPaths.baseDirectory().appending(path: "history.json"))
let turns = try JSONDecoder().decode([MLXConversationHistory.Turn].self, from: saved)
```

### Run on the Simulator (UI only)

You can build and run on the Simulator to iterate on UI without a device:

```bash
xcodebuild build -project Onyx/Onyx.xcodeproj -scheme Onyx \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The Simulator launches the app and renders the full UI. Model downloads work too — only chatting hits the Metal unavailability error, because the Simulator has no GPU. This is the expected behaviour.

---

## 13. Troubleshooting

### "No devices" in the scheme picker

- Make sure your iPhone is plugged in and unlocked.
- Check that Developer Mode is enabled (Settings → Privacy & Security → Developer Mode).
- Try a different cable — some third-party cables are charge-only.

### "Untrusted Developer" on the iPhone

Go to **Settings → General → VPN & Device Management**, find your Apple ID entry, and tap **Trust**.

### App crashes immediately on launch

- **iOS 27 beta?** Onyx does not yet support the iOS 27 beta — it crashes before the app's own code runs. Use a device on iOS 17–26 until this is resolved.
- Otherwise, open the Xcode console (**View → Debug Area → Activate Console**) and look for the crash log. Common causes:
  - **Metal unavailable** — you accidentally ran on a Simulator; switch to your physical device.
  - **Signing error** — rebuild after fixing the team/bundle ID.

### Download stalls or fails

- The downloader logs events to `<AppSupport>/Onyx/Models/.cache/download-log.txt`. View it via **Files app → On My iPhone → Onyx → Models → .cache**.
- Downloads are resumable — kill the app and relaunch, then tap **Download** again from where it left off.
- If HuggingFace is slow, try again later. The `mlx-community` repos are public and rate-limit burst downloads.

### Model loads but generates garbage

This usually means the model's chat template wasn't applied correctly. Check that `MLXConversationHistory.buildMessages(systemPrompt:)` is being called and the messages array is non-empty before generation. Look in `ChatProvider.swift` → `buildGenerationStream()`.

### Build fails after pulling new changes

Swift package resolution can get confused after dependency updates. Try:

```bash
# In Terminal, from the project root:
xcodebuild -project Onyx/Onyx.xcodeproj -scheme Onyx \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resolvePackageDependencies
```

Or in Xcode: **File → Packages → Reset Package Caches**.

---

## 14. Learning resources

### Swift and Xcode

| Resource | What you'll learn |
|---|---|
| [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/) | Swift syntax, types, generics, optionals — the official book, free online |
| [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) | `async`/`await`, actors, `AsyncStream` — essential for understanding Onyx's architecture |
| [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui) | Building declarative UIs — official Apple tutorial series |
| [@Observable](https://developer.apple.com/documentation/observation) | The new observation framework used by `ChatProvider` (iOS 17+) |
| [Running on a Device](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) | Provisioning, wireless debugging, Xcode device manager |
| [Enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) | The iOS 16+ opt-in step |

### On-device ML and MLX

| Resource | What you'll learn |
|---|---|
| [mlx-swift-lm on GitHub](https://github.com/ml-explore/mlx-swift-lm) | The Swift package powering Onyx's inference engine |
| [swift-transformers on GitHub](https://github.com/huggingface/swift-transformers) | HuggingFace tokenizers in Swift — handles chat templates |
| [mlx-community on HuggingFace](https://huggingface.co/mlx-community) | Catalogue of iPhone-compatible 4-bit quantised models |
| [Apple Metal](https://developer.apple.com/metal/) | The GPU API MLX uses under the hood on Apple Silicon |
| [Core ML vs MLX](https://github.com/ml-explore/mlx-swift-lm#readme) | Why Onyx uses MLX instead of Core ML for LLMs |

### iOS memory management

| Resource | What you'll learn |
|---|---|
| [AsyncStream](https://developer.apple.com/documentation/swift/asyncstream) | How token streaming works in Swift |
| [Increased Memory Limit Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_kernel_increased-memory-limit) | The entitlement that lets Onyx hold a 2 GB model on 6 GB devices |

---

## Quick-reference card

```
Clone       git clone … && open Onyx/Onyx.xcodeproj
Sign        Targets → Signing & Capabilities → set Team + unique Bundle ID
Trust       iPhone: Settings → Privacy & Security → Developer Mode → On
Build       ⌘R (device selected in scheme picker)
Trust app   Settings → General → VPN & Device Management → Trust
Download    Models tab → Download (auto-activates when done)
Chat        Chat tab → type message → send
Log         Xcode console: 📨 [Onyx] lines
Add model   ChatModelCatalog.swift → append ChatModelDescriptor to .all
```
