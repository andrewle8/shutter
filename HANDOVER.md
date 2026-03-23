# Shutter Fork — Handover

## What's Done
- Forked andrewle8/shutter
- Cloned to `~/repos/dodoshot`
- Remotes: `origin` = your fork, `upstream` = original repo
- Version: 1.4.5 (latest, released 2026-03-19)

## The Settings Bug
**Symptom:** Clicking "Settings..." from the menu bar opens a blank window (title bar visible, no content).

**Root cause:** `AppDelegate.openSettingsWindow()` creates a manual `NSWindow` with `NSHostingView(rootView: SettingsView())`. On macOS 26 with `.accessory` activation policy (no dock icon, which is the default), the SwiftUI content inside `NSHostingView` fails to render.

**The app has TWO settings paths:**
1. SwiftUI `Settings` scene in `ShutterApp.body` (Cmd+, path)
2. Manual `NSWindow` + `NSHostingView` in `AppDelegate.openSettingsWindow()` (menu click path)

Path 2 is broken on macOS 26.

**Fix approach (pick one):**
- **Option A (simple):** In `openSettingsWindow()`, temporarily switch to `.regular` activation policy before showing the window, then switch back when it closes. Add `NSApp.setActivationPolicy(.regular)` before `makeKeyAndOrderFront`, and restore `.accessory` in the window delegate's `windowWillClose`.
- **Option B (cleaner):** Remove the manual `NSWindow` entirely. Use `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` (or the macOS 14+ `SettingsLink`) to open the native SwiftUI Settings scene from the menu item. This eliminates the dual-path problem.
- **Option C (belt and suspenders):** Keep the NSWindow but call `window.contentView?.needsLayout = true` and `window.contentView?.layout()` after setting the `NSHostingView`, forcing an immediate render pass.

**Recommended: Option B** — it's the cleanest, removes dead code, and uses Apple's intended API.

**Files to modify:**
- `DodoShot/DodoShotApp.swift` — lines ~193-217 (`openSettingsWindow()` method), and the `openSettings()` call

## Key Architecture Notes
- Pure SwiftUI app, menu bar only (`.accessory` policy by default)
- Uses ScreenCaptureKit (modern API) for capture
- Vision framework for OCR
- `SettingsManager.shared` — singleton for all preferences
- `PermissionManager.shared` — polls every 5s for screen recording + accessibility
- Ad-hoc signed (not notarized, not App Store)
- MIT license — do whatever you want

## File Structure
```
DodoShot/
  DodoShotApp.swift          — App entry + AppDelegate (settings window, menu bar, hotkeys)
  Views/
    Settings/SettingsView.swift  — TabView with General, AI, About tabs
    MenuBarView.swift            — Popover content
    Capture/                     — Screen capture UI
    Annotation/                  — Image annotation editor
    Overlay/                     — Capture overlay
    Permissions/                 — Onboarding permission flow
    History/                     — Recent captures
  Services/                      — ScreenCaptureService, HotkeyManager, etc.
  Models/                        — Data models
  Extensions/                    — Swift extensions
```

## Next Steps
1. Fix the settings bug (Option B recommended)
2. Build and test: `open DodoShot.xcodeproj` then Cmd+R
3. Decide what to customize (hotkeys, UI, features to strip/add)
