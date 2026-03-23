import Foundation
import Carbon
import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Registered hotkey bindings: keyCode -> [(modifiers, action)]
    private var hotkeyBindings: [UInt16: [(CGEventFlags, () -> Void)]] = [:]

    private init() {}

    func registerHotkeys() {
        // Check accessibility permissions without prompting
        let trusted = AXIsProcessTrusted()

        if !trusted {
            print("Accessibility permissions required for global hotkeys")
            return
        }

        // Already registered, don't register again
        if eventTap != nil {
            return
        }

        // Build bindings from settings
        rebuildBindings()

        // Create event tap for key combinations
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return HotkeyManager.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: nil
        )

        guard let eventTap = eventTap else {
            print("Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// Re-register hotkeys after settings change (tear down and rebuild bindings, reuse tap)
    func reregisterHotkeys() {
        rebuildBindings()
    }

    /// Build the lookup dictionary from current settings
    private func rebuildBindings() {
        hotkeyBindings.removeAll()

        let settings = SettingsManager.shared.settings.hotkeys

        // Area capture
        if let parsed = HotkeyManager.parseHotkeyString(settings.areaCapture) {
            let action: () -> Void = {
                DispatchQueue.main.async {
                    ScreenCaptureService.shared.startCapture(type: .area)
                }
            }
            hotkeyBindings[parsed.keyCode, default: []].append((parsed.modifiers, action))
        }

        // Window capture
        if let parsed = HotkeyManager.parseHotkeyString(settings.windowCapture) {
            let action: () -> Void = {
                DispatchQueue.main.async {
                    ScreenCaptureService.shared.startCapture(type: .window)
                }
            }
            hotkeyBindings[parsed.keyCode, default: []].append((parsed.modifiers, action))
        }

        // Fullscreen capture
        if let parsed = HotkeyManager.parseHotkeyString(settings.fullscreenCapture) {
            let action: () -> Void = {
                DispatchQueue.main.async {
                    ScreenCaptureService.shared.startCapture(type: .fullscreen)
                }
            }
            hotkeyBindings[parsed.keyCode, default: []].append((parsed.modifiers, action))
        }
    }

    private static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let shared = HotkeyManager.shared

        if let entries = shared.hotkeyBindings[keyCode] {
            for (requiredModifiers, action) in entries {
                if matchesModifiers(flags, required: requiredModifiers) {
                    action()
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Check if the event flags match the required modifier flags
    private static func matchesModifiers(_ eventFlags: CGEventFlags, required: CGEventFlags) -> Bool {
        let hasCmd = eventFlags.contains(.maskCommand)
        let hasShift = eventFlags.contains(.maskShift)
        let hasCtrl = eventFlags.contains(.maskControl)
        let hasAlt = eventFlags.contains(.maskAlternate)

        let needCmd = required.contains(.maskCommand)
        let needShift = required.contains(.maskShift)
        let needCtrl = required.contains(.maskControl)
        let needAlt = required.contains(.maskAlternate)

        return hasCmd == needCmd && hasShift == needShift && hasCtrl == needCtrl && hasAlt == needAlt
    }

    func unregisterHotkeys() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        hotkeyBindings.removeAll()
    }

    // MARK: - Hotkey String Parsing

    /// Parse a hotkey display string like "⌘⇧4" into keyCode + modifiers
    static func parseHotkeyString(_ string: String) -> (keyCode: UInt16, modifiers: CGEventFlags)? {
        var modifiers: CGEventFlags = []
        var remaining = string

        // Strip modifier symbols from the front
        while !remaining.isEmpty {
            let first = remaining.first!
            switch first {
            case "⌘":
                modifiers.insert(.maskCommand)
                remaining.removeFirst()
            case "⇧":
                modifiers.insert(.maskShift)
                remaining.removeFirst()
            case "⌃":
                modifiers.insert(.maskControl)
                remaining.removeFirst()
            case "⌥":
                modifiers.insert(.maskAlternate)
                remaining.removeFirst()
            default:
                // Done with modifiers, rest is the key
                break
            }
            if remaining.first != "⌘" && remaining.first != "⇧" && remaining.first != "⌃" && remaining.first != "⌥" {
                break
            }
        }

        // The remaining text is the key name
        let keyName = remaining.trimmingCharacters(in: .whitespaces)
        guard !keyName.isEmpty else { return nil }
        guard modifiers.rawValue != 0 else { return nil }

        guard let keyCode = keyCodeForKeyName(keyName) else { return nil }
        return (keyCode, modifiers)
    }

    /// Convert a display string key name to a macOS virtual key code
    private static func keyCodeForKeyName(_ name: String) -> UInt16? {
        // Single character keys
        if name.count == 1 {
            let char = name.uppercased().first!
            switch char {
            case "A": return 0
            case "S": return 1
            case "D": return 2
            case "F": return 3
            case "H": return 4
            case "G": return 5
            case "Z": return 6
            case "X": return 7
            case "C": return 8
            case "V": return 9
            case "B": return 11
            case "Q": return 12
            case "W": return 13
            case "E": return 14
            case "R": return 15
            case "Y": return 16
            case "T": return 17
            case "1": return 18
            case "2": return 19
            case "3": return 20
            case "4": return 21
            case "5": return 23
            case "6": return 22
            case "7": return 26
            case "8": return 28
            case "9": return 25
            case "0": return 29
            case "O": return 31
            case "U": return 32
            case "I": return 34
            case "P": return 35
            case "L": return 37
            case "J": return 38
            case "K": return 40
            case "N": return 45
            case "M": return 46
            case "-": return 27
            case "=": return 24
            case "[": return 33
            case "]": return 30
            case ";": return 41
            case "'": return 39
            case ",": return 43
            case ".": return 47
            case "/": return 44
            case "`": return 50
            case "\\": return 42
            default: return nil
            }
        }

        // Named keys
        switch name.lowercased() {
        case "space": return 49
        case "return", "enter": return 36
        case "tab": return 48
        case "delete", "backspace": return 51
        case "escape", "esc": return 53
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        case "f5": return 96
        case "f6": return 97
        case "f7": return 98
        case "f8": return 100
        case "f9": return 101
        case "f10": return 109
        case "f11": return 103
        case "f12": return 111
        case "left", "←": return 123
        case "right", "→": return 124
        case "down", "↓": return 125
        case "up", "↑": return 126
        default: return nil
        }
    }

    // MARK: - Key Code to Display String

    /// Convert keyCode + NSEvent modifiers to a display string like "⌘⇧4"
    static func displayString(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""

        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.shift)   { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        guard let keyName = keyNameForKeyCode(keyCode) else { return "" }
        result += keyName
        return result
    }

    /// Convert a macOS virtual key code to a display string
    private static func keyNameForKeyCode(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}
