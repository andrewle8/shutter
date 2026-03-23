# CLAUDE.md

**Lucida** — a free, open-source screen-to-AI bridge for macOS. OCR-first, designed for Claude Code. Forked from DodoShot, completely rebuilt.

## Build & Deploy

```bash
cd ~/repos/lucida
xcodebuild -project DodoShot.xcodeproj -scheme DodoShot -configuration Release build CONFIGURATION_BUILD_DIR=/tmp/dodoshot-build
pkill -x Lucida; sleep 1
rm -rf /Applications/Lucida.app && cp -R /tmp/dodoshot-build/Lucida.app /Applications/Lucida.app
open /Applications/Lucida.app
```

**Signing:** Apple Development certificate, team `AXYWF78YAF`. Permissions persist across rebuilds.

**Only if permissions break** (rare — cert change or macOS revokes):
```bash
tccutil reset ScreenCapture com.lucida.app
tccutil reset Accessibility com.lucida.app
```

No unit tests. Requires Xcode 15+, macOS 14.0+ (Sonoma).

## macOS 26 Gotchas (CRITICAL — do not reintroduce these bugs)

1. **NEVER poll `SCShareableContent`** — triggers the "would like to record" system popup every time on macOS 26. Screen recording permission is checked lazily, not polled.
2. **NSWindow + NSHostingView renders BLANK** under `.accessory` activation policy — settings lives inside the popover, not a separate window. All other manual NSWindows also fail.
3. **CGEvent tap gets silently disabled** by macOS 26 for ad-hoc signed apps — `HotkeyManager.ensureTapEnabled()` polls every 5s and re-enables.
4. **TabView fails in NSHostingView** — use manual tab picker with `@State selectedTab` + `switch` instead.
5. **Permission onboarding window** — REMOVED. Prompts silently via `AXIsProcessTrustedWithOptions` once at launch.
6. **Every rebuild with ad-hoc signing invalidates TCC permissions** — solved by dev certificate signing.

## Architecture

Native SwiftUI + AppKit menu bar app. `.accessory` activation policy (no dock icon). `NSApplicationDelegateAdaptor` bridges lifecycle.

### Core Pipeline: Screen → OCR → Terminal

```
Hotkey → Area selection overlay → CGWindowListCreateImage → OCR (Vision) →
Smart format (code/table/list/error detection) → Optional LLM cleanup (Ollama) →
Clipboard → Auto-paste (AppleScript for iTerm2, CGEvent Cmd+V for others)
```

### Services (singleton, `static let shared`)

| Service | Purpose |
|---------|---------|
| **ScreenCaptureService** | Central orchestrator. Area/window/fullscreen/scrolling/OCR/timed. Routes to editor or auto-paste. |
| **SmartCaptureService** | One-hotkey capture: area select → OCR → floating prompt bar → compose message → paste |
| **OCRService** | Vision framework. Layout-aware extraction, auto-detects code/table/list/error/prose, markdown output |
| **OCRPostProcessor** | Optional Ollama LLM cleanup (localhost:11434). Fixes OCR artifacts, reformats. Default OFF. |
| **HotkeyManager** | CGEvent tap. Parses hotkey strings from settings. 18 configurable bindings. Conflict detection. |
| **SettingsManager** | UserDefaults JSON. Migration chain: DodoShot → Shutter → Lucida |
| **HistoryStore** | Disk persistence in ~/Library/Application Support/Lucida/History/ |
| **ScrollingCaptureService** | Area-based auto-scroll via CGEvent. Frame stitching with overlap detection. |
| **LLMService** | Image descriptions. Default: Apple Intelligence (local). Optional: Anthropic/OpenAI API. |
| **FloatingWindowService** | Pinned always-on-top screenshots |
| **MeasurementService** | Pixel ruler, color picker |

### iTerm2 Integration

`pasteToFrontApp()` auto-detects iTerm2 and uses AppleScript `write text` injection instead of Cmd+V. Works from any app, no focus switch needed. Toggle "iTerm2" in popover quick toggles for always-on mode.

### Settings

Settings live inside the popover (gear icon → expands to 520px settings view with back button). NOT a separate window — NSWindow+NSHostingView renders blank on macOS 26.

### Key Data Types

- **Screenshot** — stores image as `Data` (PNG bytes), not NSImage. Value type. `image` property returns fresh NSImage each access.
- **AppSettings** — all preferences. Codable with `decodeIfPresent` for backward compat.
- **HotkeySettings** — 18 hotkey strings in ⌘⇧ symbol format. Parsed by HotkeyManager.
- **OCRResult** — rawText, formattedText, detectedType, detectedLanguage, lineCount
- **LucidaProject** — `.lucida` file format. JSON with PNG data + annotations.

## Bundle ID & Signing

- Bundle ID: `com.lucida.app`
- Team: `AXYWF78YAF`
- Signing identity: `Apple Development: awesomeandrew@gmail.com (992Q7HG3P3)`
- PRODUCT_NAME: `Lucida`

## Hotkeys (all configurable in Settings → Shortcuts)

| Default | Action |
|---------|--------|
| ⌘⇧Space | Smart Capture (OCR + prompt bar + paste) |
| ⌘⇧4 | Area capture |
| ⌘⇧5 | Window capture |
| ⌘⇧3 | Fullscreen |
| ⌘⇧7 | OCR → paste text |
| ⌘⇧6 | Capture → paste image |
| ⌘⇧E | Error capture → paste |
| ⌘⇧F | Capture → /tmp → paste path |
| ⌘⇧` | Code capture → markdown block → paste |
| ⌘⇧2 | Scrolling capture |
| ⌘⇧L | Re-capture last area |
| ⌘⇧W | Active window (no picker) |
| ⌘⇧C | Color picker |
| ⌘⇧R | Pixel ruler |
| ⌘⇧T | Timed capture |
| ⌘⇧8 | OCR (show result) |
| ⌘⇧1 | All-in-one (drag=area, click=window, Return=fullscreen) |
| ⌘⇧⌥3 | All screens |
