import Foundation
import AppKit
import Combine

/// Manager for handling Screen Recording and Accessibility permissions
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    /// Whether screen recording permission is granted
    @Published var isScreenRecordingGranted: Bool = false

    /// Whether accessibility permission is granted
    @Published var isAccessibilityGranted: Bool = false

    /// Timer for checking permission status
    private var checkTimer: Timer?

    /// Flag to prevent repeated screen recording checks while system dialog is open
    private var isCheckingScreenRecording: Bool = false

    private init() {
        checkPermissions()
        // Don't auto-start monitoring - let the UI start it when needed
    }

    deinit {
        checkTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Check all permissions
    func checkPermissions() {
        checkScreenRecordingPermission()
        checkAccessibilityPermission()
    }

    /// Check screen recording permission
    func checkScreenRecordingPermission() {
        // CGPreflightScreenCaptureAccess is the lightweight check but it caches
        // the result per-process and doesn't update when the user toggles
        // the permission in System Settings. During onboarding we need real-time
        // detection, so fall back to a minimal 1x1 test capture when preflight
        // returns false — CGWindowListCreateImage returns nil when not permitted.
        var hasAccess = CGPreflightScreenCaptureAccess()

        if !hasAccess {
            // Try a minimal capture to check if permission was just granted
            let testImage = CGWindowListCreateImage(
                CGRect(x: 0, y: 0, width: 1, height: 1),
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            )
            hasAccess = testImage != nil
        }

        DispatchQueue.main.async { [weak self] in
            if self?.isScreenRecordingGranted != hasAccess {
                self?.isScreenRecordingGranted = hasAccess
            }
        }
    }

    /// Check accessibility permission
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()

        // Also check with options for more detailed info
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trustedWithOptions = AXIsProcessTrustedWithOptions(options)

        NSLog("[PermissionManager] Accessibility AXIsProcessTrusted: %@, WithOptions: %@",
              trusted ? "true" : "false",
              trustedWithOptions ? "true" : "false")

        // Use the result from AXIsProcessTrustedWithOptions as it's more reliable
        var finalResult = trusted || trustedWithOptions

        // Ad-hoc signed apps can't be reliably detected by AXIsProcessTrusted
        // even when the user has enabled them in System Settings. Allow bypass.
        if !finalResult {
            if UserDefaults.standard.bool(forKey: "accessibilityBypassed") {
                finalResult = true
            }
        }

        DispatchQueue.main.async { [weak self] in
            if self?.isAccessibilityGranted != finalResult {
                NSLog("[PermissionManager] Accessibility changed to: %@", finalResult ? "true" : "false")
                self?.isAccessibilityGranted = finalResult
            }
        }
    }

    /// Bypass accessibility check (ad-hoc signed apps can't be reliably detected)
    func bypassAccessibility() {
        UserDefaults.standard.set(true, forKey: "accessibilityBypassed")
        isAccessibilityGranted = true
    }

    /// Request screen recording permission
    func requestScreenRecordingPermission() {
        // Open System Settings to Screen Recording via AppleScript
        let script = """
            tell application "System Settings"
                activate
                reveal anchor "Privacy_ScreenCapture" of pane id "com.apple.settings.PrivacySecurity.extension"
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                let fallback = """
                    tell application "System Settings"
                        activate
                        reveal anchor "Privacy_ScreenCapture" of pane id "com.apple.settings.PrivacySecurity"
                    end tell
                    """
                NSAppleScript(source: fallback)?.executeAndReturnError(nil)
            }
        }

        // Also trigger the system prompt
        CGRequestScreenCaptureAccess()
    }

    /// Request accessibility permission
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { [weak self] in
            self?.isAccessibilityGranted = trusted
        }
        return trusted
    }

    /// Open Screen Recording settings
    func openScreenRecordingSettings() {
        requestScreenRecordingPermission()
    }

    /// Trigger the screen recording system prompt
    func triggerScreenRecordingPrompt() {
        CGRequestScreenCaptureAccess()
    }

    /// Open Accessibility settings in Privacy & Security
    func openAccessibilitySettings() {
        // URL schemes for Privacy panes are unreliable across macOS versions.
        // Use AppleScript which works on Sonoma, Sequoia, and Tahoe.
        let script = """
            tell application "System Settings"
                activate
                reveal anchor "Privacy_Accessibility" of pane id "com.apple.settings.PrivacySecurity.extension"
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: try without .extension suffix (older macOS)
                let fallback = """
                    tell application "System Settings"
                        activate
                        reveal anchor "Privacy_Accessibility" of pane id "com.apple.settings.PrivacySecurity"
                    end tell
                    """
                NSAppleScript(source: fallback)?.executeAndReturnError(nil)
            }
        }
    }

    /// Show app in Finder (for drag and drop to settings)
    func showAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.selectFile(bundleURL.path, inFileViewerRootedAtPath: bundleURL.deletingLastPathComponent().path)
    }

    /// Restart the app
    func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return }

        let script = """
            sleep 0.5
            open "\(bundlePath)"
            """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        try? task.run()

        NSApp.terminate(nil)
    }

    /// Start monitoring for permission changes
    func startMonitoring() {
        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    /// Stop monitoring
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Whether all required permissions are granted
    var allPermissionsGranted: Bool {
        isScreenRecordingGranted && isAccessibilityGranted
    }
}
